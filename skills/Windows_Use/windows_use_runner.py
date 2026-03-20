import argparse
import asyncio
import importlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


PROVIDER_MAP = {
    "openrouter": ("windows_use.providers.open_router", "ChatOpenRouter"),
    "openai": ("windows_use.providers.openai", "ChatOpenAI"),
    "anthropic": ("windows_use.providers.anthropic", "ChatAnthropic"),
    "google": ("windows_use.providers.google", "ChatGoogle"),
    "groq": ("windows_use.providers.groq", "ChatGroq"),
    "ollama": ("windows_use.providers.ollama", "ChatOllama"),
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def install_mistralai_compat_shim() -> None:
    """Patch newer mistralai layouts so windows-use can import optional Mistral support.

    windows-use imports all providers at package import time, including its Mistral
    provider, even when the active provider is OpenRouter/OpenAI/etc. Some newer
    mistralai distributions expose `Mistral` and `models` under `mistralai.client`
    instead of the top-level `mistralai` package. This shim restores the import
    surface that windows-use expects without changing the configured provider.
    """
    try:
        mistralai_pkg = importlib.import_module("mistralai")
    except Exception:
        return

    if hasattr(mistralai_pkg, "Mistral") and "mistralai.models" in sys.modules:
        return

    try:
        client_module = importlib.import_module("mistralai.client")
        models_module = importlib.import_module("mistralai.client.models")
    except Exception:
        return

    compat_class = getattr(client_module, "Mistral", None)
    if compat_class is not None and not hasattr(mistralai_pkg, "Mistral"):
        setattr(mistralai_pkg, "Mistral", compat_class)

    if "mistralai.models" not in sys.modules:
        sys.modules["mistralai.models"] = models_module
    if not hasattr(mistralai_pkg, "models"):
        setattr(mistralai_pkg, "models", models_module)


def patch_windows_use_registry() -> None:
    """Await async tools inside windows-use's sync execution path.

    windows-use 0.7.65 exposes async tool functions but its sync Registry.execute()
    calls them without awaiting, which returns coroutine objects and causes the
    agent to fail after every tool call. Monkey-patch the sync path to await when
    needed while preserving the original ToolResult contract.
    """
    from windows_use.agent.registry.service import Registry
    from windows_use.agent.registry.views import ToolResult

    if getattr(Registry.execute, "__name__", "") == "_execute_with_async_support":
        return

    def _execute_with_async_support(self, tool_name: str, tool_params: dict, desktop=None) -> ToolResult:
        tool = self.get_tool(tool_name)
        if not tool:
            return ToolResult(is_success=False, error=f"Tool '{tool_name}' not found.")

        errors = tool.validate_params(tool_params)
        if errors:
            error_msg = "\n".join(errors)
            return ToolResult(is_success=False, error=f"Tool '{tool_name}' validation failed:\n{error_msg}")

        invoke_kwargs = ({"desktop": desktop} | tool_params)
        try:
            if asyncio.iscoroutinefunction(getattr(tool, "function", None)):
                try:
                    content = asyncio.run(tool.ainvoke(**invoke_kwargs))
                except RuntimeError:
                    loop = asyncio.new_event_loop()
                    try:
                        asyncio.set_event_loop(loop)
                        content = loop.run_until_complete(tool.ainvoke(**invoke_kwargs))
                    finally:
                        asyncio.set_event_loop(None)
                        loop.close()
            else:
                content = tool.invoke(**invoke_kwargs)
        except Exception as error:
            error_msg = str(error)
            return ToolResult(is_success=False, error=f"Tool '{tool_name}' execution failed:\n{error_msg}")

        if content is not None and not isinstance(content, str):
            content = str(content)
        return ToolResult(is_success=True, content=content)

    Registry.execute = _execute_with_async_support


def write_jsonl(log_path: str | None, payload: dict) -> None:
    if not log_path:
        return
    path = Path(log_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False, default=str) + "\n")


def summarize_event(event_type: str, data: object) -> str:
    if isinstance(data, dict):
        if event_type == "TOOL_CALL":
            tool_name = data.get("tool_name", "unknown_tool")
            return f"TOOL_CALL {tool_name}"
        if event_type == "TOOL_RESULT":
            tool_name = data.get("tool_name", "unknown_tool")
            return f"TOOL_RESULT {tool_name}"
        if event_type == "DONE":
            answer = str(data.get("answer", "")).strip().replace("\n", " ")
            return f"DONE {answer[:180]}"
        if event_type == "ERROR":
            error_text = str(data.get("error", data)).strip().replace("\n", " ")
            return f"ERROR {error_text[:180]}"
        thought = data.get("thought")
        if thought:
            return f"{event_type} {str(thought).strip().replace(chr(10), ' ')[:180]}"
    return f"{event_type} {str(data).strip().replace(chr(10), ' ')[:180]}"


def task_likely_requires_desktop_actions(task: str) -> bool:
    action_markers = (
        "open ",
        "launch ",
        "click ",
        "type ",
        "write ",
        "switch ",
        "press ",
        "scroll ",
        "drag ",
        "calculator",
        "notepad",
        "outlook",
        "browser",
        "window",
    )
    lowered = task.strip().lower()
    return any(marker in lowered for marker in action_markers)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a bounded Windows-Use task.")
    parser.add_argument("--task", required=True)
    parser.add_argument("--provider", default="openrouter")
    parser.add_argument("--model", required=True)
    parser.add_argument("--reasoning-effort", default="")
    parser.add_argument("--browser", default="edge")
    parser.add_argument("--max-steps", type=int, default=30)
    parser.add_argument("--mode", default="normal")
    parser.add_argument("--log-file", default="")
    parser.add_argument("--use-vision", action="store_true")
    parser.add_argument("--experimental", action="store_true")
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()

    os.environ.setdefault("ANONYMIZED_TELEMETRY", "false")
    install_mistralai_compat_shim()

    try:
        from windows_use.agent import Agent, Browser
    except Exception as exc:
        print(f"[WINDOWS_USE_ERROR] windows-use is not installed or failed to import: {exc}", file=sys.stderr)
        return 2

    patch_windows_use_registry()

    provider_key = args.provider.strip().lower()
    if provider_key not in PROVIDER_MAP:
        print(f"[WINDOWS_USE_ERROR] Unsupported provider: {args.provider}", file=sys.stderr)
        return 2

    module_name, class_name = PROVIDER_MAP[provider_key]
    try:
        provider_module = importlib.import_module(module_name)
        provider_class = getattr(provider_module, class_name)
    except Exception as exc:
        print(f"[WINDOWS_USE_ERROR] Could not load provider '{args.provider}': {exc}", file=sys.stderr)
        return 2

    provider_kwargs = {}
    reasoning_effort = args.reasoning_effort.strip().lower()
    if provider_key == "openrouter" and reasoning_effort and reasoning_effort != "none":
        provider_kwargs["extra_body"] = {"reasoning": {"effort": reasoning_effort}}

    try:
        llm = provider_class(model=args.model, **provider_kwargs)
    except Exception as exc:
        print(f"[WINDOWS_USE_ERROR] Could not initialize provider '{args.provider}' with model '{args.model}': {exc}", file=sys.stderr)
        return 2

    browser_name = args.browser.strip().upper()
    browser_value = getattr(Browser, browser_name, None)
    if browser_value is None:
        print(f"[WINDOWS_USE_ERROR] Unsupported browser: {args.browser}", file=sys.stderr)
        return 2

    event_stats = {
        "events": 0,
        "tool_calls": 0,
        "non_done_tool_calls": 0,
    }

    def on_event(event) -> None:
        event_type_obj = getattr(event, "type", None)
        event_type = getattr(event_type_obj, "value", str(event_type_obj))
        data = getattr(event, "data", {})
        event_stats["events"] += 1
        if event_type.lower() == "tool_call":
            event_stats["tool_calls"] += 1
            tool_name = str(data.get("tool_name", ""))
            if tool_name != "done_tool":
                event_stats["non_done_tool_calls"] += 1
        payload = {
            "timestamp": utc_now(),
            "type": event_type,
            "data": data,
        }
        write_jsonl(args.log_file or None, payload)
        print(summarize_event(event_type, data))

    try:
        agent = Agent(
            llm=llm,
            browser=browser_value,
            mode=args.mode,
            use_vision=args.use_vision,
            use_accessibility=True,
            max_steps=args.max_steps,
            log_to_console=False,
            log_to_file=False,
            event_subscriber=on_event,
            experimental=args.experimental,
        )
        result = agent.invoke(task=args.task)
    except Exception as exc:
        error_payload = {
            "timestamp": utc_now(),
            "type": "RUNNER_ERROR",
            "data": {"error": str(exc)},
        }
        write_jsonl(args.log_file or None, error_payload)
        print(f"[WINDOWS_USE_ERROR] {exc}", file=sys.stderr)
        if args.debug:
            raise
        return 1

    final_text = getattr(result, "content", None)
    if final_text is None:
        final_text = str(result)

    if task_likely_requires_desktop_actions(args.task) and event_stats["non_done_tool_calls"] == 0:
        error_text = "Model reported task completion without invoking any desktop tool actions."
        write_jsonl(
            args.log_file or None,
            {
                "timestamp": utc_now(),
                "type": "RUNNER_ERROR",
                "data": {
                    "error": error_text,
                    "event_count": event_stats["events"],
                    "tool_calls": event_stats["tool_calls"],
                },
            },
        )
        print(f"[WINDOWS_USE_ERROR] {error_text}", file=sys.stderr)
        return 1

    write_jsonl(
        args.log_file or None,
        {
            "timestamp": utc_now(),
            "type": "FINAL_RESULT",
            "data": {"content": final_text},
        },
    )
    print("\n=== WINDOWS-USE RESULT ===")
    print(final_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

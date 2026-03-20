import argparse
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


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a bounded Windows-Use task.")
    parser.add_argument("--task", required=True)
    parser.add_argument("--provider", default="openrouter")
    parser.add_argument("--model", required=True)
    parser.add_argument("--browser", default="edge")
    parser.add_argument("--max-steps", type=int, default=30)
    parser.add_argument("--mode", default="normal")
    parser.add_argument("--log-file", default="")
    parser.add_argument("--use-vision", action="store_true")
    parser.add_argument("--experimental", action="store_true")
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()

    os.environ.setdefault("ANONYMIZED_TELEMETRY", "false")

    try:
        from windows_use.agent import Agent, Browser
    except Exception as exc:
        print(f"[WINDOWS_USE_ERROR] windows-use is not installed or failed to import: {exc}", file=sys.stderr)
        return 2

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

    try:
        llm = provider_class(model=args.model)
    except Exception as exc:
        print(f"[WINDOWS_USE_ERROR] Could not initialize provider '{args.provider}' with model '{args.model}': {exc}", file=sys.stderr)
        return 2

    browser_name = args.browser.strip().upper()
    browser_value = getattr(Browser, browser_name, None)
    if browser_value is None:
        print(f"[WINDOWS_USE_ERROR] Unsupported browser: {args.browser}", file=sys.stderr)
        return 2

    def on_event(event) -> None:
        event_type_obj = getattr(event, "type", None)
        event_type = getattr(event_type_obj, "value", str(event_type_obj))
        data = getattr(event, "data", {})
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

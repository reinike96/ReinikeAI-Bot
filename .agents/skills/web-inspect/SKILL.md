---
name: web-inspect
description: Selective inspection of one known URL before using full-page fetches. Extract only the page structure and likely data sources needed for the task.
---

# Web Inspect

Use this skill when you already know a page URL and need structured signals before deciding whether a full-body read is necessary.

## Command

```bash
node .agents/skills/web-inspect/scripts/inspect_url.js --url "https://example.com" --mode summary
```

## Modes

- `summary`: metadata + headings + links + assets + JSON-LD
- `metadata`: title, description, canonical, Open Graph, language
- `headings`: `h1`/`h2`/`h3`
- `links`: likely page links
- `assets`: JS/JSON/RSS/sitemap/data hints
- `asset`: inspect a discovered JS/JSON/XML/RSS asset and return only structured signals

## Use it for

- known-page inspection
- landing pages that hide article links behind scripts
- finding feeds, JSON, JS, sitemap, or API hints
- extracting page structure without pulling full content into context

## Workflow

1. Run the script on the exact URL you already have.
2. Use the JSON output to identify titles, dates, slugs, links, and data sources.
3. If the page is an SPA shell, rerun the same script on the most relevant discovered asset with `--mode asset`.
4. Only read full page or article bodies after the target item is known.

Example second hop:

```bash
node .agents/skills/web-inspect/scripts/inspect_url.js --url "https://example.com/path/data.js" --mode asset
```

## Rules

- Do not guess derived routes like `/blog` before inspecting the provided root URL.
- Do not read large JS/JSON assets linearly into context if only a few fields are needed.
- Prefer extracting titles, dates, slugs, URLs, headings, and asset hints first.
- If the downstream goal is copywriting, drafting, or posting, stop at the smallest useful source package first: title, URL, date, and 1-3 key points or excerpt hints.
- Do not fetch or summarize a full article body unless the task explicitly needs deeper content than that minimal source package.
- If `summary` reveals an asset that likely contains the answer, inspect that asset with `--mode asset` before using `WebFetch`.
- Use browser automation only after the inspection phase if interaction is actually required.

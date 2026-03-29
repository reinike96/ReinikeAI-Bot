---
name: research-report
user-invocable: true
description: Convert deep research JSON results into a markdown report.
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
---

# Research Report

## Trigger
`/research-report`

## Workflow

### Step 1: Locate Results
Find `*/outline.yaml`, read the topic and configured `output_dir`.

### Step 2: Ask for Summary Fields
Read the JSON results and offer short fields that make sense in the table of contents, such as:
- `release_date`
- `github_stars`
- `valuation`
- `google_scholar_cites`
- `user_scale`

### Step 3: Generate a Report Script
Create `{topic}/generate_report.py` that:
- reads all JSON files from `output_dir`
- reads `fields.yaml`
- covers all fields defined in `fields.yaml`
- skips values marked `[uncertain]`
- skips fields listed in the `uncertain` array
- supports flat and nested JSON shapes
- writes `{topic}/report.md`

### Step 4: Execute the Script
Run `python {topic}/generate_report.py`

## Output
- `{topic}/generate_report.py`
- `{topic}/report.md`

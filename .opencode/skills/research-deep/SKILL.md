---
name: research-deep
user-invocable: true
description: Read the research outline and run deep research per item using background agents.
allowed-tools: Bash, Read, Write, Glob, WebSearch, Task
---

# Research Deep

## Trigger
`/research-deep`

## Workflow

### Step 1: Auto-locate Outline
Find `*/outline.yaml` in the current working directory and read the items plus execution config.

### Step 2: Resume Check
- inspect completed JSON files in `output_dir`
- skip completed items

### Step 3: Batch Execution
- process in batches by `batch_size`
- each agent handles `items_per_agent`
- launch the `web-search` agent in background mode with task output disabled

Each worker should:
- read `fields.yaml`
- write structured JSON to the configured result path
- mark uncertain values with `[uncertain]`
- maintain an `uncertain` array
- keep field values in English
- run validation with `validate_json.py`

### Step 4: Wait and Monitor
- wait for the current batch
- launch the next batch
- show progress

### Step 5: Summary Report
After completion, report:
- completion count
- failed or uncertain items
- output directory

---
user-invocable: true
description: Add items to an existing research outline.
allowed-tools: Bash, Read, Write, Glob, WebSearch, Task, AskUserQuestion
---

# Research Add Items

## Trigger
`/research-add-items`

## Workflow

### Step 1: Auto-locate Outline
Find `*/outline.yaml` in the current working directory and read it.

### Step 2: Get Supplement Sources
In parallel:
- ask the user which items to supplement
- decide whether to launch a web-search agent to find more items

### Step 3: Merge and Update
- append new items to `outline.yaml`
- avoid duplicates
- show the update for confirmation
- save the outline

## Output
Updated `{topic}/outline.yaml`

---
user-invocable: true
description: Add field definitions to an existing research outline.
allowed-tools: Bash, Read, Write, Glob, WebSearch, Task, AskUserQuestion
---

# Research Add Fields

## Trigger
`/research-add-fields`

## Workflow

### Step 1: Auto-locate Fields File
Find `*/fields.yaml` in the current working directory and read the existing field definitions.

### Step 2: Get Supplement Source
Ask the user to choose:
- direct field input
- web-search-assisted field discovery

### Step 3: Display and Confirm
- Show suggested new fields
- Let the user confirm which fields to add
- Let the user specify category and `detail_level`

### Step 4: Save Update
Append the confirmed fields to `fields.yaml` and save it.

## Output
Updated `{topic}/fields.yaml`

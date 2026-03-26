---
user-invocable: true
allowed-tools: Read, Write, Glob, WebSearch, Task, AskUserQuestion
description: Conduct preliminary research on a topic and generate a research outline.
---

# Research Skill - Preliminary Research

## Trigger
`/research <topic>`

## Workflow

### Step 1: Generate Initial Framework from Model Knowledge
Based on topic, use model knowledge to generate:
- Main research objects/items in the domain
- Suggested research field framework

Output `{step1_output}` and use `AskUserQuestion` to confirm:
- Need to add or remove items?
- Does the field framework meet the requirement?

### Step 2: Web Search Supplement
Use `AskUserQuestion` to ask for a time range such as the last 6 months, since 2024, or unlimited.

### Step 3: Ask User for Existing Fields
Ask if the user has an existing field-definition file. If so, read and merge it.

### Step 4: Generate Outline Files
Merge the initial framework, supplement results, and any user-supplied fields. Generate:

`outline.yaml`
- `topic`
- `items`
- `execution.batch_size`
- `execution.items_per_agent`
- `execution.output_dir` with default `./results`

`fields.yaml`
- field categories and definitions
- each field's `name`, `description`, and `detail_level`
- reserve `uncertain` as the list auto-filled in the deep phase

### Step 5: Output and Confirm
- Create `./{topic_slug}/`
- Save `outline.yaml` and `fields.yaml`
- Show them to the user for confirmation

## Output Path
`{cwd}/{topic_slug}/`

## Follow-up Commands
- `/research-add-items`
- `/research-add-fields`
- `/research-deep`

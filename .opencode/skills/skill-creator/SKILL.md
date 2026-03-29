---
name: skill-creator
description: Guide for creating new skills. Use when you need to create, document, and assign a new skill based on a task you've successfully completed.
---

# Skill Creator Guide

## What is a Skill?

A skill is a reusable set of instructions stored in `.opencode/skills/<skill-name>/SKILL.md` that helps agents perform specific tasks consistently.

## When to Create a Skill

Create a skill when:
- You've successfully completed a task and want to preserve the workflow
- A task is complex enough to benefit from step-by-step documentation
- Multiple agents might need to perform the same task
- The user asks you to "create a skill" for something

## ⚠️ CRITICAL: Do NOT Delegate Skill Creation

**You must perform the task yourself when creating a skill.**

Why:
- You need to SEE the actual output of commands
- You need to UNDERSTAND what works and what doesn't
- Delegating to subagents means you lose direct visibility
- The skill must contain YOUR learned knowledge, not second-hand information

**Example:** When creating a skill to fetch the latest post from a website:
- ❌ WRONG: Delegate to @browser agent to inspect the site
- ✅ RIGHT: Use webfetch yourself, see the HTML structure, test the API endpoints

## Skill Creation Process

### Step 1: Perform the Task Manually

First, do the task yourself and learn what works:
- Try different approaches
- Note what commands/tools worked
- Identify edge cases and errors
- Find the optimal workflow
- **DO NOT delegate this step**

### Step 2: Document What Worked

Write down:
- The exact commands that worked
- The correct order of operations
- Error handling solutions
- Important notes and caveats

### Step 3: Create the Skill File

Create the skill structure:
```
.opencode/skills/<skill-name>/
└── SKILL.md
```

### Step 4: Write SKILL.md

Use this template:

```markdown
---
name: skill-name
description: Brief description of what the skill does. Use when [trigger conditions].
allowed-tools: Bash(command:*), Read(*), etc.
category: content|automation|research|etc.
---

# Skill Title

## When to Use

- Condition 1
- Condition 2

## Steps

### Step 1: [Action]
```bash
exact command that works
```

### Step 2: [Action]
```bash
exact command that works
```

## Important Notes

- Critical thing to remember
- Common pitfalls to avoid
```

### Step 5: Assign to Agent (Optional)

If the skill should be used by a specific agent, update the agent's config:

**File:** `.opencode/agents/<agent>.md`

```yaml
permission:
  skill:
    skill-name: "allow"
```

And add to the agent's description:
```markdown
- [Capability description] (use the skill-name skill)
```

## Skill Best Practices

| Do | Don't |
|----|-------|
| Use exact commands that work | Use vague instructions |
| Include error handling | Assume everything works |
| Keep it simple and focused | Make overly complex skills |
| Test the skill after creating | Skip testing |
| Document edge cases | Ignore special situations |

## Example: Creating the youtube-transcript Skill

1. **Performed task:** Extracted transcript using cdp-cli.js commands
2. **Learned:** Need to pause video, click transcript button, wait, extract
3. **Created:** `.opencode/skills/youtube-transcript/SKILL.md`
4. **Assigned:** Added to browser agent permissions

## Quick Reference

| File | Purpose |
|------|---------|
| `SKILL.md` | Main skill instructions |
| `.js` or `.ps1` | Optional helper scripts |
| `agents/*.md` | Agent configurations |

## Skill Location

All skills are in:
```
.opencode/skills/
├── playwright-cli/
├── research/
├── youtube-transcript/
├── skill-creator/      ← This skill
└── ...
```

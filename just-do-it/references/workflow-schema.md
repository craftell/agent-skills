# Workflow YAML Schema Reference

## Complete Schema

```yaml
name: workflow-name
description: Brief description of the workflow

steps:
  - name: step-name           # Required: Unique step identifier
    agent: agent-type         # Required: Sub-agent type (must be valid subagent_type)
    prompt: |                 # Required: Instructions for sub-agent
      Multi-line prompt...
    report:                   # Optional: Output report configuration
      name: report-name       # Required if report: Filename without extension
      format: |               # Required if report: Markdown template (advisory)
        ## Report Template
        ...
      validation: "REGEX"     # Optional: Regex pattern to validate output
    next: next-step           # Optional: Default next step name
    end: true                 # Optional: If true, completes workflow
    conditions:               # Optional: Conditional transitions
      - keyword: KEYWORD      # Required: Keyword to match
        goto: target-step     # Required: Step name to transition to
```

## Parallel Steps Schema

```yaml
- name: parallel-step
  parallel:                   # Use parallel instead of agent/prompt
    - agent: agent-type-1
      prompt: |
        Instructions for first agent...
    - agent: agent-type-2
      prompt: |
        Instructions for second agent...
  check: all                  # "all" = all must pass, "any" = first pass wins
  report:
    name: report-name
    format: |
      ## Parallel Results
      ...
    validation: "APPROVED|REJECTED"
  conditions:
    - keyword: APPROVED
      goto: next-step
    - keyword: REJECTED
      goto: retry-step
```

## Step Fields Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Unique step identifier |
| `agent` | string | Yes* | Sub-agent type (*not for parallel) |
| `prompt` | string | Yes* | Instructions for sub-agent (*not for parallel) |
| `parallel` | array | No | Array of {agent, prompt} for parallel execution |
| `check` | string | No | "all" or "any" for parallel steps |
| `report` | object | No | Output report configuration |
| `report.name` | string | Yes if report | Report filename (without extension) |
| `report.format` | string | Yes if report | Markdown template (guidance only) |
| `report.validation` | string | No | Regex pattern to validate output |
| `next` | string | No | Default next step name |
| `end` | boolean | No | If true, this step completes workflow |
| `conditions` | array | No | Conditional transitions |
| `conditions[].keyword` | string | Yes | Keyword to match |
| `conditions[].goto` | string | Yes | Step name to transition to |

## Reserved Keywords

| Keyword | Purpose |
|---------|---------|
| `TASK_DONE` | Short-circuit to completion when task needs no work |

## Important Rules

1. **Entry point**: First step in YAML is the entry point
2. **No `goto: end`**: Use `end: true` on final step instead
3. **Conditions use `goto`**: `end: true` is only valid at step level
4. **Parallel reports**: Written as `{step_name}_{index}.md`
5. **`check: all`**: Any failure/rejection keyword wins over approvals

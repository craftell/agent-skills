# Workflow YAML Schema Reference

## Complete Schema

```yaml
name: workflow-name
description: Brief description of the workflow

steps:
  - name: step-name           # Required: Unique step identifier
    agent: agent-type         # Optional: Sub-agent type (must be valid subagent_type)
                              #   If omitted, prompt runs directly on the orchestrator
    prompt: |                 # Required: Instructions for sub-agent (or orchestrator if no agent)
      Multi-line prompt...
    report:                   # Optional: Output report configuration
      name: report-name       # Required if report: Filename without extension
      format: |               # Required if report: Markdown template (advisory)
        ## Report Template
        ...
      validation: "REGEX"     # Optional: Regex pattern to validate output
    human: true               # Optional: Requires --human flag to execute
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
  human: true                 # Optional: Gates entire parallel execution
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
| `agent` | string | No | Sub-agent type. If omitted (and not parallel), prompt runs directly on the orchestrator |
| `prompt` | string | Yes* | Instructions for sub-agent or orchestrator (*not for parallel) |
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
| `human` | boolean | No | When true, step requires `--human` flag. Defaults to false. On parallel steps: gates entire parallel execution. NOT allowed on individual agents within parallel block. |

## Inline Execution (No Agent)

When `agent` is omitted from a step, the orchestrator executes the prompt directly instead of delegating to a sub-agent via the Task tool. This is useful for lightweight steps that don't need a separate agent context, such as file transformations, simple validations, or aggregation of prior reports.

```yaml
- name: summarize
  prompt: |
    Read the reports from prior steps and produce a summary...
  report:
    name: summary
    format: |
      ## Summary
      ...
    validation: "SUMMARY_COMPLETE"
  end: true
```

All other step features (reports, validation, conditions, human gates, next/end) work identically for inline steps.

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
6. **Parallel agents require `agent`**: Each entry in a `parallel` block must specify `agent`. Inline execution (omitting `agent`) is only supported for non-parallel steps
7. **Completion semantics of `end: true`**: `end: true` on a step means the workflow is complete ONLY when that step finishes without a condition redirecting elsewhere. A step can have both `end: true` and `conditions` — if a condition matches, the condition's `goto` takes priority and the workflow continues. The `end: true` flag is only honored when no condition matches.

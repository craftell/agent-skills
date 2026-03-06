# Workflow YAML Schema Reference

## Complete Schema

```yaml
name: workflow-name
description: Brief description of the workflow

steps:
  # --- Standard step (single agent) ---
  - name: step-name           # Required: Unique step identifier
    agent: agent-type         # Optional: Sub-agent type. Default: general-purpose
    prompt: |                 # Instructions for sub-agent
      Multi-line prompt...
    prompt_file: path/to/prompt.md  # Alternative: load prompt from file (relative to workflow dir)
    report:                   # Optional: Output report configuration
      name: report-name       # Required if report: Filename without extension
      format: |               # Markdown template (structure + language are authoritative)
        ## Report Template
        ...
      format_file: path/to/format.md  # Alternative: load format from file (relative to workflow dir)
      validation: "REGEX"     # Optional: Regex pattern to validate output
    human: true               # Optional: Requires --human flag to execute
    next: next-step           # Optional: Default next step name
    end: true                 # Optional: If true, completes workflow
    conditions:               # Optional: Conditional transitions
      - keyword: KEYWORD      # Required: Keyword to match
        goto: target-step     # Required: Step name to transition to

  # --- Parallel step (multiple agents) ---
  - name: parallel-step-name  # Required: Unique step identifier
    parallel:                 # Replaces agent/prompt/prompt_file for this step
      - agent: agent-type     # Optional: Sub-agent type per branch. Default: general-purpose
        prompt: |             # Instructions for this branch's agent
          ...
        prompt_file: path.md  # Alternative: load prompt from file
      - agent: agent-type
        prompt_file: path.md
    check: all                # Required for parallel: aggregation strategy (see below)
    report:                   # Optional: same as standard step
      name: report-name
      format: |
        ...
      validation: "REGEX"
    next: next-step
    conditions:               # Optional: same as standard step
      - keyword: KEYWORD
        goto: target-step
```

## Step Fields Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Unique step identifier |
| `agent` | string | No | Sub-agent type. Default: `general-purpose` (standard steps only) |
| `prompt` | string | Yes* | Instructions for sub-agent (mutually exclusive with `prompt_file`; standard steps only) |
| `prompt_file` | string | No | Path to prompt file, relative to workflow directory (mutually exclusive with `prompt`; standard steps only) |
| `parallel` | array | No | List of parallel branches (mutually exclusive with `agent`/`prompt`/`prompt_file`) |
| `parallel[].agent` | string | No | Sub-agent type for this branch. Default: `general-purpose` |
| `parallel[].prompt` | string | Yes* | Prompt for this branch (mutually exclusive with `prompt_file`) |
| `parallel[].prompt_file` | string | No | Path to prompt file for this branch (mutually exclusive with `prompt`) |
| `check` | string | Yes if parallel | Aggregation strategy: `all` = every branch must pass |
| `report` | object | No | Output report configuration |
| `report.name` | string | Yes if report | Report filename (without extension) |
| `report.format` | string | Yes if report | Markdown template — structure and language are authoritative (mutually exclusive with `format_file`) |
| `report.format_file` | string | No | Path to format template file, relative to workflow directory (mutually exclusive with `format`) |
| `report.validation` | string | No | Regex pattern to validate output |
| `next` | string | No | Default next step name |
| `end` | boolean | No | If true, this step completes workflow |
| `conditions` | array | No | Conditional transitions |
| `conditions[].keyword` | string | Yes | Keyword to match |
| `conditions[].goto` | string | Yes | Step name to transition to |
| `human` | boolean | No | When true, step requires `--human` flag. Defaults to false. |

## Reserved Keywords

| Keyword | Purpose |
|---------|---------|
| `TASK_DONE` | Short-circuit to completion when task needs no work |

## File References

Steps support loading prompts from external files instead of inline YAML. Report blocks support loading format templates from files.

- **`prompt_file`**: Path to a file whose contents are used as the step/agent prompt. Relative to the workflow file's parent directory.
- **`format_file`**: Path to a file whose contents are used as the report format template. Relative to the workflow file's parent directory.

**Rules:**
- `prompt` and `prompt_file` are **mutually exclusive** — specifying both on the same step is a validation error (ABORT).
- `format` and `format_file` are **mutually exclusive** — specifying both on the same report is a validation error (ABORT).
- One of `prompt` or `prompt_file` is required for each step.
- If the referenced file does not exist, the orchestrator ABORTs with the resolved path in the error message.

**Example:**
```yaml
steps:
  - name: review
    prompt_file: assets/prompts/review.prompt.md   # loaded at runtime
    report:
      name: review
      format: |                                     # inline format (could also use format_file)
        ## Review Result
        ...
      validation: "APPROVED|REJECTED"
```

## Parallel Steps

A step can run multiple sub-agents concurrently by using `parallel` instead of `agent`/`prompt`/`prompt_file`. Each entry in the `parallel` array is an independent branch with its own agent and prompt.

**Fields:**
- `parallel`: Array of branches. Each branch has `agent` (optional, default `general-purpose`) and `prompt` or `prompt_file` (one required, mutually exclusive).
- `check`: Aggregation strategy. Required when `parallel` is used.
  - `all` — Every branch must produce a passing result. If any branch fails (e.g., outputs `REJECTED`), the step as a whole fails.

**Execution:**
1. All branches are dispatched concurrently via the Agent tool (parallel tool calls).
2. Each branch receives the same task context (title, description, feedback) combined with its own prompt.
3. All branch outputs are concatenated into a single combined output for the step.
4. The combined output is validated against `report.validation` (if present) and used for condition matching as usual.

**Mutual exclusivity:** A step must use either `parallel` or `agent`/`prompt`/`prompt_file`, never both. Specifying both is a validation error (ABORT).

**Example:**
```yaml
- name: be-review
  parallel:
    - agent: general-purpose
      prompt_file: assets/prompts/be-review-event-modeling.prompt.md
    - agent: general-purpose
      prompt_file: assets/prompts/be-review-emmett.prompt.md
  check: all
  report:
    name: be-review
    format: |
      ## Backend Review Result
      **Status:** APPROVED | REJECTED
      ...
    validation: "APPROVED|REJECTED"
  next: fe-implementation
  conditions:
    - keyword: APPROVED
      goto: fe-implementation
    - keyword: REJECTED
      goto: be-implementation
```

## Important Rules

1. **Entry point**: First step in YAML is the entry point
2. **No `goto: end`**: Use `end: true` on final step instead
3. **Conditions use `goto`**: `end: true` is only valid at step level
4. **Completion semantics of `end: true`**: `end: true` on a step means the workflow is complete ONLY when that step finishes without a condition redirecting elsewhere. A step can have both `end: true` and `conditions` — if a condition matches, the condition's `goto` takes priority and the workflow continues. The `end: true` flag is only honored when no condition matches.

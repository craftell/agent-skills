# Workflow YAML Schema Reference

## Complete Schema

```yaml
name: workflow-name                # Required: Workflow identifier

steps:
  step-name:                       # Key is the unique step identifier
    agent: agent-type              # Optional: Sub-agent type (default: general-purpose)
    prompt: |                      # Required: Instructions for sub-agent
      Multi-line prompt...
    human: true                    # Optional: Requires --human flag to execute
    next:                          # Required: Routing array (evaluated top-to-bottom)
      - if: KEYWORD                # Optional: Match against <!-- DECISION: KEYWORD -->
        goto: target-step          # Required: Step name or "end"
      - goto: fallback-step        # Last entry without `if` is the default/fallback
```

## Parallel Steps Schema

```yaml
  parallel-step:
    parallel:                      # Use parallel instead of agent/prompt
      - agent: agent-type-1        # Required: Each parallel agent must specify type
        prompt: |
          Instructions for first agent...
      - agent: agent-type-2
        prompt: |
          Instructions for second agent...
    check: all                     # "all" = all must match, "any" = first match wins
    human: true                    # Optional: Gates entire parallel execution
    next:
      - if: APPROVED
        goto: next-step
      - if: REJECTED
        goto: retry-step
      - goto: retry-step           # Fallback
```

## Step Fields Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| (key) | string | Yes | Unique step identifier (the YAML map key) |
| `agent` | string | No | Sub-agent type. Defaults to `general-purpose` if omitted |
| `prompt` | string | Yes* | Instructions for sub-agent (*not used for parallel steps) |
| `parallel` | array | No | Array of `{agent, prompt}` for parallel execution |
| `check` | string | No | `"all"` or `"any"` for parallel decision aggregation |
| `human` | boolean | No | When true, step requires `--human` flag. On parallel steps: gates entire execution. NOT allowed on individual agents within parallel block |
| `next` | array | Yes | Routing array. Evaluated top-to-bottom. First `if` match wins. Last entry without `if` is the default fallback. Missing `next` is a schema validation error |
| `next[].if` | string | No | Decision keyword to match against `<!-- DECISION: KEYWORD -->` |
| `next[].goto` | string | Yes | Target step name, or `"end"` to terminate workflow |

## Decision Block Convention

Agents communicate routing decisions by including a structured comment at the end of their output:

```
<!-- DECISION: KEYWORD -->
```

### Rules

- The orchestrator extracts the keyword from the **last 5 lines** of agent output
- Extraction uses: `echo "$output" | tail -5 | grep -oP '<!-- DECISION: \K\w+' | tail -1`
- The keyword is matched against the step's `next` array
- **Terminal steps** (`next: [- goto: end]` with no `if` entries) skip decision parsing entirely — no `<!-- DECISION -->` needed
- **Missing keyword**: If no keyword found and the step has conditional routing, the fallback route is taken and a lesson is recorded

### Parallel Decision Aggregation

- Each parallel agent includes `<!-- DECISION: KEYWORD -->` in its output
- `check: all` — All agents must produce the same keyword for it to match. If agents disagree, the default/fallback route is taken
- `check: any` — The `next` array is walked top-to-bottom; for each `if` entry, if ANY agent produced that keyword, the route is taken

## Important Rules

1. **Entry point**: First step in the YAML map is the entry point
2. **`next` is required**: Every step must have a `next` array. Missing `next` is a schema validation error — fail fast
3. **Completion**: Only `goto: end` completes a workflow. There is no other completion mechanism
4. **Routing order**: The `next` array is evaluated top-to-bottom. First `if` match wins. The last entry without `if` is the default/fallback
5. **Parallel agents require `agent`**: Each entry in a `parallel` block must specify `agent`
6. **Reports**: Always written to `.jdi/reports/{task_id}/{step_name}.md`. Parallel outputs are merged into a single file
7. **`check: all`**: If parallel agents disagree on the keyword, the fallback route wins
8. **Human gate on parallel**: `human: true` gates the entire parallel block. NOT allowed on individual agents within the block

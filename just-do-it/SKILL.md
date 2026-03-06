---
name: jdi
description: Workflow orchestration for AI agents. Delegates to sub-agents, tracks state via YAML task files. Use for /jdi run, /jdi init, or /jdi add.
argument-hint: <command> [options]
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# just-do-it Workflow Orchestrator

## Core Rules

1. **Task completion is controlled exclusively by the Finalize phase.** Never set `status: completed` anywhere else. Premature completion corrupts the task queue.
2. **Always delegate to sub-agents via Agent tool.** Default agent: `general-purpose`. The orchestrator never performs task work itself.
3. **Archive completed tasks.** Move from `.jdi/tasks/` to `.jdi/archived/`.
4. **Write status to `.jdi/status`.** Every exit path must write one of: `CONTINUE`, `STEP_COMPLETE step={name}`, `WORKFLOW_COMPLETE`, `ABORT`, `HUMAN_REQUIRED`.

## Task File Format

Each task is `.jdi/tasks/NNN-slug.yaml`:

```yaml
title: Set up database schema
description: |
  Create the initial database schema...
status: pending       # pending | in_progress | completed
depends_on: []        # task filenames, e.g. ["001-setup.yaml"]
current_step: null    # workflow step name, or null
feedback: null        # review feedback
```

## Commands

| Command | Usage | Description |
|---------|-------|-------------|
| `run` | `/jdi run [--workflow NAME] [--task ID] [--human]` | Execute one workflow step |
| `init` | `/jdi init` | Interactive setup |
| `add` | `/jdi add <spec-path> [--depends-on FILE1,FILE2]` | Create task from spec |

Parse `$ARGUMENTS` — `$0` is the subcommand. Empty/unrecognized → show usage.

## run Command

Execute one workflow step, then exit. Caller handles looping.

### Execution Flow

1. **Load config** — first file found wins (no merging):
   `.jdi/config.local.yaml` → `.jdi/config.yaml` → `~/.config/jdi/config.yaml` → defaults (`default_workflow: default.yaml`).
   CLI flags override.

2. **Load workflow**
   - `--workflow`: try as path, then `.jdi/workflows/`
   - Otherwise: `default_workflow` from config
   - Validate (see references/workflow-schema.md). Record `workflow_dir` for resolving `prompt_file`/`format_file`.

3. **Get current task**
   - `--task ID`: read `.jdi/tasks/{ID}` directly
   - Otherwise: first `status: pending` task whose `depends_on` files all exist in `.jdi/archived/`. Set to `in_progress`.
   - `in_progress` tasks are valid — resume from prior session
   - No tasks → write `WORKFLOW_COMPLETE` to `.jdi/status`, exit
   - **Define `{task_id}`**: The task's filename without the `.yaml` extension (e.g., `001-add-goal.yaml` → `task_id = 001-add-goal`). All references to `{task_id}` in subsequent steps use this value. Do NOT use a run counter or numeric ID.

4. **Determine current step**
   - Read task's `current_step`
   - `null` or unknown → default to first workflow step, update task file. This is normal, not an error.

5. **Initialize orchestrator log**
   - Create `.jdi/reports/{task_id}/orchestrator.md` with preamble if it doesn't exist (use `Write`). See references/orchestrator-log-format.md.
   - Print: `Orchestrator log: .jdi/reports/{task_id}/orchestrator.md`

6. **Human gate**
   - `step.human === true` AND no `--human` → write `HUMAN_REQUIRED` to `.jdi/status`, append `⏸ PAUSED` to log, exit

7. **Execute step**
   - Resolve file references (`prompt_file`, `format_file` — relative to `workflow_dir`). Both inline and file present → ABORT.
   - **Standard step** (has `prompt`/`prompt_file`, no `parallel`):
     - Build prompt: task context (title, description, feedback) + step prompt
     - Append: `Include a "## Summary" section (2-4 sentences) at the end summarizing what you did and the outcome.`
     - If `report.format`: append `Write your report strictly following this template's structure AND language:\n\n{format}`
     - Agent: step's `agent` field, default `general-purpose`
     - Execute via Agent tool, capture output. No output → ABORT.
   - **Parallel step** (has `parallel` array):
     - For each branch in `parallel`: resolve its `prompt`/`prompt_file`, build prompt with task context + branch prompt + summary/format instructions (same as standard step).
     - Dispatch all branches concurrently via parallel Agent tool calls, each with its branch's agent (default `general-purpose`).
     - Collect all outputs. Any branch returning no output → ABORT.
     - Concatenate all branch outputs (separated by `\n\n---\n\n`) into a single combined output for subsequent steps (validation, report, conditions).
     - `check` field determines pass/fail: `all` = every branch must pass.

8. **Validate output** (only if `report.validation` exists)
   - Run `scripts/validate_output.py <pattern> <temp_file>` (script path relative to skill install directory)
   - Fail → ABORT
   - Capture matched keywords

9. **Write report** (only if `report` exists)
   - Write in the same natural language as the format template (e.g., Japanese template → Japanese report). First run → `Write`; subsequent → `Bash` with `>>` append
   - Format: `## YYYY-MM-DD HH:MM:SS\n\n{output}\n\n---`
   - Target: `.jdi/reports/{task_id}/{report.name}.md`

10. **Evaluate & update**
    - Re-read workflow YAML. Check step's `end` and `conditions`.
    - Multiple keywords → different conditions = ABORT. Invalid goto target → ABORT.
    - Determine decision:

      | `end: true`? | Condition redirects? | `TASK_DONE`? | Decision |
      |---|---|---|---|
      | Yes | No | — | COMPLETE |
      | Yes | Yes | — | CONTINUE |
      | No | — | Yes | COMPLETE |
      | No | — | No | CONTINUE |

    - If CONTINUE: update `current_step` to next step. If a condition redirected (goto fired): append agent output to task's `feedback`.
    - After write: re-read and verify `status: in_progress` + correct `current_step`. Fail → ABORT.
    - Append step entry to orchestrator log — `Bash` with `>>` heredoc (preserves inode for `tail -f`). Extract `## Summary` from output (or `(no summary provided)`). See references/orchestrator-log-format.md.

11. **Finalize**
    - **COMPLETE** (only when step 10 determined COMPLETE):
      - Print: `✓ Completing: step={name} end={true/false} keywords={matched} reason={reason}`
      - Set `status: completed`, clear `current_step`, move task to `.jdi/archived/`
      - Append completion entry to log
      - Write `.jdi/reports/{task_id}/summary.md` (same language as templates)
      - Write `STEP_COMPLETE step={name}` to `.jdi/status`
    - **ABORT**: write `ABORT` to `.jdi/status`
    - **CONTINUE**: write `CONTINUE` to `.jdi/status`

## init Command

1. Copy `assets/templates/jdi_template/` to `./.jdi/`
2. Create `.jdi/tasks/` and `.jdi/archived/`
3. Ask for default workflow name → update `config.yaml`

## add Command

`/jdi add <spec-path> [--depends-on FILE1,FILE2]`

1. Read spec file, extract title from first heading/line
2. Read the full spec to generate an accurate task description:
   - Summarize what the spec covers (backend API, frontend UI, or both)
   - Reference the spec file path
   - Do NOT narrow the scope — if the spec includes UI/frontend sections, mention them.
     The description must reflect the spec's full scope, not just one aspect.
   - Example: "Implement the AddGoal feature: backend command slice (events, handler, route, tests) and frontend UI (quick-add bar, full form with validation). Spec: path/to/spec.md"
3. Next number: max prefix in `.jdi/tasks/*.yaml` + 1, zero-padded to 3 digits
4. Slug: lowercase, hyphenated, alphanumeric
5. Create `.jdi/tasks/NNN-slug.yaml` with `status: pending`
6. Set `depends_on` if `--depends-on` provided
7. Print: `Created task: NNN-slug.yaml`

---
name: jdi
description: Workflow orchestration for AI agents. Runs workflows that delegate to sub-agents, tracks state via task management, and operates autonomously. Use when user wants to run automated workflows with /jdi run, initialize workflow config with /jdi init, check status with /jdi status, or promote lessons with /jdi apply-lessons. Designed to run in bash while loops until COMPLETE or ABORT.
argument-hint: <command> [options]
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, Skill
---

# just-do-it Workflow Orchestrator

## Argument Parsing

The subcommand is `$0` (first argument). Parse `$ARGUMENTS` to extract command and options:

| Command | Usage | Description |
|---------|-------|-------------|
| `run` | `/jdi run [--workflow NAME] [--task ID] [--stop-on-complete]` | Execute one workflow step |
| `init` | `/jdi init` | Interactive setup |
| `status` | `/jdi status` | Show current state |
| `apply-lessons` | `/jdi apply-lessons` | Promote lessons to rules |

**Parsing flags from `$ARGUMENTS`:**
- `--workflow NAME`: Extract workflow name/path after `--workflow`
- `--task ID`: Extract task ID after `--task`
- `--stop-on-complete`: Boolean flag, true if present

If `$0` is empty or unrecognized, show usage help.

## run Command

Execute one workflow step, then exit. Caller handles looping.

### Execution Flow

1. **Check prerequisites**
   - Verify `task-management` skill exists (fail fast if not)
   - Read `.jdi/config.yaml` (use defaults if missing)

2. **Acquire lock**
   - Check `.jdi/locks/{task_id}.lock`
   - If exists, abort with lock error
   - Create lock file

3. **Load workflow**
   - If `--workflow` specified: try as file path, then lookup in `.jdi/workflows/`
   - Otherwise: use `default_workflow` from config (default: `default.yaml`)
   - Parse YAML, validate structure (see references/workflow-schema.md)

4. **Get current task**
   - If `--task ID` specified: use that task
   - Otherwise: invoke `/task-management next`
   - If `NO_TASKS_AVAILABLE` or task already complete: write `COMPLETE` to status, release lock, exit

5. **Get task context**
   - Invoke `/task-management context`
   - Parse current step from subject prefix (e.g., `[review]` → step is `review`)
   - If no prefix or prefix doesn't match a step name: use first step

6. **Execute step**
   - Find step definition in workflow
   - Build prompt: task context + step prompt
   - If parallel step: use Task tool for each agent (run concurrently)
   - Otherwise: use Task tool with step's agent type
   - Capture output

7. **Validate output**
   - Write output to temp file
   - Run `scripts/validate_output.py <pattern> <temp_file>`
   - If validation fails (exit code 1): abort workflow
   - Capture matched keywords from stdout

8. **Write report**
   - Create `.jdi/reports/{task_id}/` directory if needed
   - Write output to `{step_name}.md` (or `{step_name}_{index}.md` for parallel)

9. **Evaluate conditions**
   - Check matched keywords against step's conditions
   - If multiple keywords match different conditions: abort (ambiguous)
   - If `TASK_DONE` in keywords: skip to completion
   - Determine next step via conditions or `next` field
   - If `end: true` and no condition matches: workflow complete

10. **Update task**
    - If transitioning to different step: invoke `/task-management update --step "new-step"`
    - If rejected or error with feedback: invoke `/task-management update --feedback "..."`

11. **Record lessons** (REJECTED only)
    - Append to `.jdi/LESSONS.md`:
    ```markdown
    ## {date} - Task #{id}, Step: {step_name}

    **Trigger:** REJECTED

    **Lesson:** {rejection reason from output}
    ```

12. **Write execution log**
    - Write to `.jdi/logs/{task_id}_{step_name}_{agent}.json`
    - Include: timestamp, task_id, step_name, agent_type, keywords_found, transition, duration_ms
    - If `verbose_logs: true` in config: include full output

13. **Determine status and write**
    - If workflow complete:
      - Invoke `/task-management complete`
      - Write summary to `.jdi/reports/{task_id}/summary.md`
      - If `--stop-on-complete` or `auto_continue: false`: write `COMPLETE`
      - Otherwise: write `CONTINUE` (for next task)
    - If error/abort: write `ABORT`
    - If more steps: write `CONTINUE`

14. **Release lock**
    - Delete `.jdi/locks/{task_id}.lock`

### Parallel Step Handling

For steps with `parallel` key:
1. Launch all agents concurrently via Task tool
2. Collect all outputs
3. Validate each output
4. Determine combined result:
   - `check: all`: Any failure/rejection keyword wins
   - `check: any`: First pass keyword wins
5. Write separate reports: `{step_name}_0.md`, `{step_name}_1.md`, etc.

### Error Handling

| Scenario | Action |
|----------|--------|
| No output from sub-agent | Write ABORT, release lock |
| Validation fails | Write ABORT, release lock |
| Multiple ambiguous keyword matches | Write ABORT, release lock |
| Invalid goto target | Write ABORT, release lock |
| Lock file exists | Fail immediately with lock error |
| Workflow file not found | Fail with instructions |
| Prefix update fails | Write ABORT, release lock |

## init Command

Interactive setup for new projects.

1. Create `.jdi/` directory structure
2. Ask for task management skill name (default: `task-management`)
3. Ask for default workflow name
4. Create `.jdi/config.yaml`:
   ```yaml
   task_skill: task-management
   default_workflow: default.yaml
   auto_continue: true
   verbose_logs: false
   ```
5. Create `.jdi/workflows/default.yaml` with example workflow
6. Display path to task-management template: `Show user: assets/task-management.skill`
7. Instruct user to copy and customize the template

## status Command

Display current workflow state.

1. Read `.jdi/status` file
2. Invoke `/task-management context`
3. Read workflow file from config
4. Output:
   ```
   Status: {CONTINUE|COMPLETE|ABORT}
   Task: #{id} - {title}
   Workflow: {workflow name}
   Current Step: {step name}
   ```

## apply-lessons Command

Promote lessons from LESSONS.md to permanent rules.

1. Read `.jdi/LESSONS.md`
2. If empty, inform user and exit
3. Generalize specific lessons into reusable rules
4. Ask user where to save:
   - CLAUDE.md
   - .claude/rules/*.md
   - Other location
5. Append rules to chosen file
6. Archive to `.jdi/lessons_archive/lessons_{date}.md`
7. Clear `.jdi/LESSONS.md`

## Directory Structure

Auto-create directories as needed:

```
.jdi/
├── config.yaml
├── status
├── workflows/
│   └── default.yaml
├── reports/{task_id}/
│   ├── {step_name}.md
│   └── summary.md
├── locks/{task_id}.lock
├── logs/{task_id}_{step_name}_{agent}.json
├── lessons_archive/
└── LESSONS.md
```

## Resources

- **scripts/validate_output.py**: Validates sub-agent output against regex patterns
- **references/workflow-schema.md**: Complete workflow YAML schema reference
- **assets/task-management.skill**: Template for task-management skill (user must copy)
- **assets/sample-workflow.yaml**: Complete example workflow (plan → implement → review → finalize)
- **assets/just-do-it.sh**: Bash loop runner with configurable max iterations

## Bash Loop Usage

Use `assets/just-do-it.sh` for production loop execution:

```bash
# Copy to project root
cp /path/to/just-do-it/assets/just-do-it.sh ./

# Run with defaults (max 100 iterations)
./just-do-it.sh

# Run with custom max iterations
./just-do-it.sh -m 50

# Run unlimited until COMPLETE/ABORT
./just-do-it.sh -m 0

# Run specific workflow and task
./just-do-it.sh -w code-review -t 123

# Stop after current task (don't continue to next)
./just-do-it.sh -s

# Show verbose output
./just-do-it.sh -v
```

Exit codes: `0` = COMPLETE, `1` = ABORT, `2` = max iterations reached

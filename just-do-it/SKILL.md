---
name: jdi
description: Workflow orchestration for AI agents. Runs workflows that delegate to sub-agents, tracks state via task management, and operates autonomously. Use when user wants to run automated workflows with /jdi run, initialize workflow config with /jdi init, check status with /jdi status, or promote lessons with /jdi apply-lessons. Designed to run in bash while loops until WORKFLOW_COMPLETE or ABORT.
argument-hint: <command> [options]
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, Skill
# NOTE: TaskCreate, TaskUpdate, TaskList, TaskGet are intentionally EXCLUDED.
# All task operations go through the task-management skill via the Skill tool.
---

# just-do-it Workflow Orchestrator

## CRITICAL RULE — Task Operations Must Use the Skill Tool

**NEVER call built-in `TaskCreate`, `TaskUpdate`, `TaskList`, or `TaskGet` tools directly.** Every task operation MUST go through the `task-management` skill (or the skill name configured in `task_skill`) using the **Skill tool**.

### Correct (Skill tool)

```
Skill: task-management, args: "next"
Skill: task-management, args: "context"
Skill: task-management, args: "complete"
Skill: task-management, args: "update --step \"review\""
Skill: task-management, args: "update --feedback \"needs error handling\""
```

### WRONG (built-in tools) — NEVER DO THIS

```
TaskList          ← FORBIDDEN
TaskGet           ← FORBIDDEN
TaskUpdate        ← FORBIDDEN
TaskCreate        ← FORBIDDEN
```

### Why

The `task-management` skill is an abstraction layer. Users may back it with GitHub Issues, Linear, or another system — not just Claude's built-in task tools. Bypassing it:
- Breaks when the backend is not Claude's built-in task tools
- Skips the skill's step-prefix parsing, status transitions, and output formatting
- Produces output the orchestrator cannot parse

### Self-Check (apply before EVERY task operation)

> "Am I about to call a built-in `TaskXxx` tool?" → **STOP.** Use `Skill: task-management` instead.

---

## CRITICAL RULE — Task Completion

**NEVER mark a task as `complete` unless the workflow has fully finished for that task.** Premature completion corrupts the task queue and causes subsequent `/task-management next` calls to skip unfinished work.

### Mandatory Checklist — Before calling `/task-management complete`

You MUST answer this question YES. If NO → write `CONTINUE`, do NOT complete.

1. Did step 11 (routing evaluation) resolve to `goto: end`?

That is the **ONLY** completion signal. No other step output, keyword, or agent message means the workflow is complete.

### Common Mistakes to Avoid

- **The sub-agent says "Done! Task complete."** → This does NOT mean the workflow is complete. The agent is reporting its step output. Only `goto: end` in the routing determines completion.
- **You finished executing a step and it succeeded** → The workflow likely has more steps (review, finalize). Write `CONTINUE`.

## CRITICAL RULE — Lock Cleanup

**ALWAYS release the lock file before exiting.** A leftover lock file permanently blocks all subsequent loop iterations, killing the entire workflow. This is never acceptable.

Once the lock is acquired (step 7), step 16 (release lock) is a **mandatory finally block** — it MUST execute regardless of success, failure, abort, or any error in steps 8–15. There are no exceptions. Every code path after step 7 must reach step 16.

When any step in 8–15 encounters an error:
1. Perform the error handling for that step (write ABORT, log error, etc.)
2. **Then unconditionally proceed to step 16** to release the lock
3. Only after the lock is deleted may the orchestrator exit

Never exit, abort, or return between steps 7 and 16 without deleting the lock file.

## Argument Parsing

The subcommand is `$0` (first argument). Parse `$ARGUMENTS` to extract command and options:

| Command | Usage | Description |
|---------|-------|-------------|
| `run` | `/jdi run [--workflow NAME] [--task ID] [--human]` | Execute one workflow step |
| `init` | `/jdi init` | Interactive setup |
| `status` | `/jdi status` | Show current state |
| `apply-lessons` | `/jdi apply-lessons` | Promote lessons to rules |

**Parsing flags from `$ARGUMENTS`:**
- `--workflow NAME`: Extract workflow name/path after `--workflow`
- `--task ID`: Extract task ID after `--task`
- `--human`: Boolean flag, true if present. Approves the next human-gated step.

If `$0` is empty or unrecognized, show usage help.

## run Command

Execute one workflow step, then exit. Caller handles looping.

### Execution Flow

1. **Check prerequisites**
   - Verify `task-management` skill exists (fail fast if not)
   - Verify `CLAUDE_CODE_TASK_LIST_ID` is set (check environment variable). If not set, warn: `⚠ CLAUDE_CODE_TASK_LIST_ID is not set. Task list will not persist across sessions. Add it to .claude/settings.json — see init command.`
   - Resolve config (first file found wins — no merging between layers):
     1. `.jdi/config.local.yaml` → use it
     2. `.jdi/config.yaml` → use it
     3. `~/.config/jdi/config.yaml` → use it
     4. No file found → use all hardcoded defaults
   - Parse the active file as YAML. If invalid YAML, error immediately (do NOT fall through).
   - Apply hardcoded defaults for any missing keys:
     ```yaml
     task_skill: task-management
     default_workflow: default.yaml
     ```
   - Unknown keys are silently ignored.
   - CLI flags (`--workflow`, `--task`) override the resolved values.

2. **Load workflow**
   - If `--workflow` specified: try as file path, then lookup in `.jdi/workflows/`
   - Otherwise: use `default_workflow` from config (default: `default.yaml`)
   - Parse YAML, validate structure (see references/workflow-schema.md)
   - Validate that every step has a `next` array. Missing `next` is a schema error — fail fast with a clear message.

3. **Get current task**
   - If `--task ID` specified: use that task
   - Otherwise: invoke `/task-management next` **(⚠ use Skill tool, NOT built-in TaskList/TaskGet)**
   - If `NO_TASKS_AVAILABLE` or task already complete: write `WORKFLOW_COMPLETE` to status, exit

4. **Get task context**
   - Invoke `/task-management context` **(⚠ use Skill tool, NOT built-in TaskGet)**
   - Parse current step from subject prefix (e.g., `[review]` → step is `review`)
   - If no prefix or prefix doesn't match a step name: use first step

5. **Initialize orchestrator log**
   - Create `.jdi/reports/{task_id}/` directory if needed
   - If `.jdi/reports/{task_id}/orchestrator.md` does **not** exist:
     - Use `Write` tool to create it with the **preamble** (see Orchestrator Log Format below)
     - This is the only time `Write` is used on this file — all later writes use `Bash` with `>>` to preserve the inode for `tail -f`
   - If it already exists: skip (content from prior steps in the same task is preserved)
   - Print: `Orchestrator log: .jdi/reports/{task_id}/orchestrator.md`

6. **Human gate check**
   - If `step.human === true` AND `--human` flag is NOT present:
     - Write `HUMAN_REQUIRED` to `.jdi/status`
     - Append a `⏸ PAUSED` entry to the orchestrator log using `Bash` with a heredoc and `>>` (preserves inode for `tail -f`)
     - Print: `ABORT: Step "{step_name}" requires --human flag. Run: /jdi run --human`
     - Exit immediately. No lock acquired. No lock to release.
   - If `step.human === true` AND `--human` IS present: proceed normally
   - If `step.human` is not set or `false`: proceed normally regardless of `--human` flag
   - **Validation:** If a parallel step has `human: true` on individual agents within the `parallel` block, that is an invalid configuration — write `ABORT`, print validation error, exit (no lock held at this point)

7. **Acquire lock**
   - Check `.jdi/locks/{task_id}.lock`
   - If the lock file exists:
     - Read its contents (it contains a timestamp — see below)
     - If the lock is older than **10 minutes**: it is stale (the previous session likely crashed). Force-remove it, print `⚠ Removed stale lock (created {timestamp}, age {N}m)`, and continue to acquire
     - If the lock is 10 minutes old or less: abort with lock error (another session is likely active)
   - Create lock file containing the current ISO-8601 timestamp: `echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .jdi/locks/{task_id}.lock`
   - **From this point forward, step 16 (release lock) is mandatory.** Every code path — success, error, or abort — must reach step 16 before exiting.

8. **Execute step**
   - Find step definition in workflow
   - Build prompt: task context + step prompt
   - Determine agent type: use step's `agent` field, or `general-purpose` if not specified
   - If parallel step: use Task tool for each agent (run concurrently)
   - Else: use Task tool with the determined agent type
   - Capture output

9. **Parse decision**
   - If the step's `next` array contains only unconditional entries (no `if` fields): skip decision parsing entirely. Use the first route directly.
   - Otherwise: extract decision keyword from the last 5 lines of agent output using bash:
     ```bash
     echo "$output" | tail -5 | grep -oP '<!-- DECISION: \K\w+' | tail -1
     ```
   - If keyword found: store for routing in step 11
   - If keyword NOT found:
     - Use the default/fallback route (the `next` entry without `if`)
     - Record a lesson in `.jdi/LESSONS.md` with trigger `MISSING_DECISION`
   - For **parallel steps**: extract decisions from each agent's output separately (see Parallel Step Handling)

10. **Write report**
    - Create `.jdi/reports/{task_id}/` directory if needed
    - Use the `Write` tool to **overwrite** the report file with the latest output
    - Target file: `.jdi/reports/{task_id}/{step_name}.md`
    - For parallel steps: merge all outputs into a single `{step_name}.md` (see Parallel Step Handling for format)

11. **Evaluate routing**
    - **Re-read the workflow file** and find the current step's `next` array. Do NOT rely on memory or inference — read the actual YAML.
    - Walk the `next` array top-to-bottom:
      1. If entry has `if` field: compare against extracted decision keyword. If match → use this route.
      2. If entry has no `if` field: this is the default/fallback. Use it.
    - If `goto: end`: workflow is complete for this task
    - If `goto: {step_name}`: workflow continues to that step
    - If no route matched (malformed `next` array — no fallback and no keyword match): write ABORT, log error, **then proceed to step 16** (release lock)
    - If `goto` target references a step that doesn't exist in the workflow: write ABORT, log error, **then proceed to step 16** (release lock)

12. **Update task**
    - If transitioning to a different step: invoke `/task-management update --step "new-step"` **(⚠ Skill tool)**
    - If rejected or error with feedback: invoke `/task-management update --feedback "..."` **(⚠ Skill tool)**

13. **Record lessons** (REJECTED or MISSING_DECISION only)
    - Append to `.jdi/LESSONS.md`:
    ```markdown
    ## {date} - Task #{id}, Step: {step_name}

    **Trigger:** {REJECTED | MISSING_DECISION}

    **Lesson:** {description of what happened and why}
    ```
    - **REJECTED**: Record the rejection reason extracted from agent output
    - **MISSING_DECISION**: Record that the agent did not include `<!-- DECISION: KEYWORD -->` and the fallback route was taken
    - Other failure modes (ABORT, crashes, lock contention) are NOT recorded as lessons — they are operational issues, not learnable workflow insights

14. **Append to orchestrator log**
    - Target file: `.jdi/reports/{task_id}/orchestrator.md` (already created in step 5)
    - Use `Bash` with a heredoc and `>>` to append. This preserves the file's inode so `tail -f` continues to work. Example: `cat >> .jdi/reports/{task_id}/orchestrator.md << 'ENTRY'\n{content}\nENTRY`
    - For error/abort scenarios, use the **error entry** format instead
    - Include the **full agent output** in a collapsible `<details>` block (see Orchestrator Log Format below)

15. **Determine status and write**
    - **CRITICAL**: Only treat the workflow as "complete" when step 11 resolved to `goto: end`.
      Do NOT infer completion from any other signal. When in doubt, write `CONTINUE`.
    - If workflow complete (`goto: end`):
      - Print: `✓ Completing: step={step_name} goto=end`
      - Invoke `/task-management complete` **(⚠ use Skill tool, NOT built-in TaskUpdate)**
      - Append the **completion entry** to the orchestrator log using `Bash` with heredoc `>>` (same inode-preserving pattern as step 14)
      - Write `STEP_COMPLETE step={step_name}` — this signals that one task's workflow finished. The caller (bash loop) decides whether to continue to the next task or stop.
    - If error/abort: write `ABORT` (the error entry was already written in step 14)
    - If more steps remain: write `CONTINUE` — do NOT invoke `/task-management complete`

16. **Release lock (MANDATORY — always runs)**
    - This step is a **finally block**: it MUST execute after step 7, regardless of outcome.
    - Delete `.jdi/locks/{task_id}.lock`
    - If the delete fails, retry once. If it still fails, print `⚠ FAILED TO RELEASE LOCK: .jdi/locks/{task_id}.lock — manual removal required` so the operator can intervene.
    - **Never exit the run command with the lock file still present.** A leftover lock permanently blocks all subsequent iterations of the bash loop.

### Parallel Step Handling

For steps with `parallel` key:
1. Launch all agents concurrently via Task tool
2. Collect all outputs
3. Extract `<!-- DECISION: KEYWORD -->` from each agent's output
4. Determine combined decision:
   - `check: all`: All agents must produce the same keyword for it to match an `if` entry. If agents disagree, take the default/fallback route.
   - `check: any`: Walk the `next` array top-to-bottom. For each `if` entry, if ANY agent produced that keyword, use that route.
5. Merge all outputs into a single `{step_name}.md` report:
   ```markdown
   ## Agent 0: {agent_type}

   {full output from agent 0}

   ---

   ## Agent 1: {agent_type}

   {full output from agent 1}

   ---
   ```
6. Log per-agent decisions in the orchestrator log for observability

### Error Handling

**Lock guarantee:** Every scenario that occurs after step 7 (lock acquired) MUST reach step 16 (release lock). The "release lock" column below is a reminder, not optional.

| Scenario | Action |
|----------|--------|
| No output from sub-agent | Write ABORT, log error, **release lock (step 16)** |
| Missing decision keyword (step has conditionals) | Use fallback route, record lesson (MISSING_DECISION), continue normally |
| No fallback route in `next` array | Write ABORT, log error, **release lock (step 16)** |
| Invalid `goto` target (step doesn't exist) | Write ABORT, log error, **release lock (step 16)** |
| Lock file exists (≤10 min old) | Fail immediately with lock error (no lock acquired) |
| Lock file exists (>10 min old) | Remove stale lock, print warning, proceed normally |
| Workflow file not found | Fail with instructions (no lock acquired) |
| Prefix update fails | Write ABORT, log error, **release lock (step 16)** |
| Human step without `--human` flag | Write `HUMAN_REQUIRED` status, print message, exit (no lock held — step 6 runs before step 7) |
| `human` property on parallel sub-agent | Write `ABORT`, print validation error, exit (no lock held — step 6 runs before step 7) |

### Orchestrator Log Format

The orchestrator log (`.jdi/reports/{task_id}/orchestrator.md`) is a human-readable, append-only markdown file designed for `tail -f`. It records every step execution so a human can follow the workflow in real time.

#### Preamble (written once when file is created)

```markdown
# Workflow Log — Task #{id}

| Field | Value |
|-------|-------|
| **Task** | #{id} — {task title} |
| **Workflow** | {workflow name} |
| **Config** | {config file path, or "defaults"} |
| **Started** | {YYYY-MM-DD HH:MM:SS} |

---
```

#### Step entry (appended after each step)

```markdown
## [{HH:MM:SS}] {previous_step} → {next_step}

| | |
|---|---|
| **Agent** | {agent type} |
| **Duration** | {N.N}s |
| **Decision** | {extracted keyword, or "(none)"} |
| **Transition** | {step_name} → {next_step} |

<details>
<summary>Full output</summary>

{complete agent output}

</details>

---
```

- The heading uses `→` to show the transition. For the first step (no previous), use: `## [{HH:MM:SS}] → {step_name}` (start).
- For end steps with no next step: `## [{HH:MM:SS}] {step_name} → DONE`.
- The `Transition` row shows the routing result. If default/fallback route, write `(fallback)`. If end, write `(end)`.
- For parallel steps, list each agent on its own row in the table and include each agent's output in a separate `<details>` block:

```markdown
| **Decision** | Agent 0: {keyword}, Agent 1: {keyword} |

<details>
<summary>Full output (Agent 0: {agent-type})</summary>

{agent 0 full output}

</details>

<details>
<summary>Full output (Agent 1: {agent-type})</summary>

{agent 1 full output}

</details>
```

#### Error entry (used for abort/error scenarios)

```markdown
## [{HH:MM:SS}] ⚠ ABORT — {step_name}

**Error:** {description of what went wrong}

<details>
<summary>Agent output (if any)</summary>

{agent output, or "(no output)" if agent produced nothing}

</details>

---
```

- Use `⚠ ABORT` in the heading so errors are immediately visible when tailing.
- For human-gate halts, use `⏸ PAUSED` instead: `## [{HH:MM:SS}] ⏸ PAUSED — {step_name}` with the message about requiring `--human`.

#### Completion entry (appended when workflow finishes for this task)

```markdown
## [{HH:MM:SS}] ✓ COMPLETE

**Task #{id}** finished in {N} steps.

---
```

## init Command

Interactive setup for new projects.

1. Copy `assets/templates/jdi_template/` directory tree to `./.jdi/`
2. Ask for task management skill name (default: `task-management`) — update `config.yaml` value
3. Ask for default workflow name — update `config.yaml` value
4. **Configure task list persistence** — Generate a UUID and add `CLAUDE_CODE_TASK_LIST_ID` to `.claude/settings.json` so the task list is shared across all sessions (required for the bash loop runner):
   - Read `.claude/settings.json` (create if it doesn't exist)
   - Add or update the `env` object with `"CLAUDE_CODE_TASK_LIST_ID": "<generated-uuid>"`
   - Preserve any existing settings in the file
   - Example result:
     ```json
     {
       "env": {
         "CLAUDE_CODE_TASK_LIST_ID": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
       }
     }
     ```
   - Print: `Task list ID configured: <uuid>`
5. Display path to task-management template: `Show user: assets/task-management.skill`
6. Instruct user to copy and customize the template

`jdi init` does NOT:
- Create or manage `~/.config/jdi/config.yaml` (user does this manually)
- Create `.jdi/config.local.yaml` (user does this manually when needed)

## status Command

Display current workflow state.

1. Read `.jdi/status` file
2. Invoke `/task-management context` **(⚠ use Skill tool, NOT built-in TaskGet)**
3. Read workflow file from config
4. Output:
   ```
   Config: .jdi/config.local.yaml
   Status: {CONTINUE|STEP_COMPLETE|WORKFLOW_COMPLETE|ABORT|HUMAN_REQUIRED}
   Task: #{id} - {title}
   Workflow: {workflow name}
   Current Step: {step name}
   ```
   Config line shows the path of the active config file, or `defaults` if no file was found.

## apply-lessons Command

Extract root causes from LESSONS.md and create rules that prevent the fundamental problem, not just the specific symptom.

**Core principle:** Specific lessons describe *what went wrong*. Good rules address *why it went wrong*. A lesson like "forgot to check for null return from getUserById" should not become a rule about getUserById — it should become a rule about defensive handling of fallible lookups. Always ask: "What is the category of mistake, and what habit or constraint eliminates the entire category?"

### Execution Flow

1. **Read** `.jdi/LESSONS.md`
2. If empty, inform user and exit
3. **Cluster** — Group lessons by underlying cause, not by surface similarity. Two lessons about different functions may share the same root cause (e.g., missing error handling at boundaries). Two lessons about the same file may have completely different root causes.
4. **Abstract** — For each cluster, perform root-cause analysis:
   - **Identify the specific incident**: What exactly happened?
   - **Ask "why" repeatedly** until you reach a structural or habitual cause (not just "I forgot"):
     - Why did the agent produce wrong output? → It didn't validate assumptions.
     - Why didn't it validate assumptions? → No step in the workflow enforces validation before proceeding.
     - **Root cause**: The workflow lacks a validation gate for assumptions.
   - **Name the category of mistake**: e.g., "boundary assumption errors", "missing state checks", "implicit coupling between steps"
   - **Formulate a rule that eliminates the category**, not just the instance. The rule should be actionable, testable, and apply broadly.
5. **Discard** — Drop lessons that are:
   - Too specific to be useful beyond a single incident (e.g., "task #42 had a typo in the config")
   - Already covered by an existing rule (check target file first)
   - One-off environmental issues (e.g., "network was down")
6. **Draft rules** — Each rule must include:
   - A clear, imperative statement of what to do or not do
   - A one-line rationale linking it to the root cause
   - The scope: when the rule applies (always? only at boundaries? only in specific step types?)
7. **Present to user** — Show the drafted rules alongside the original lessons they were derived from, so the user can verify the abstraction is correct.
8. **Ask user** where to save:
   - CLAUDE.md
   - .claude/rules/*.md
   - Other location
9. Append rules to chosen file
10. Archive to `.jdi/lessons_archive/lessons_{date}.md`
11. Clear `.jdi/LESSONS.md`

### Abstraction Quality Check

Before finalizing, verify each rule passes these tests:
- **Scope test**: Does the rule apply to more than just the original incident? If you can only imagine it triggering once, abstract further.
- **Actionability test**: Can an agent unambiguously follow this rule? Vague rules like "be more careful" fail this test.
- **Root-cause test**: If the agent follows this rule perfectly, would the *original* incident still have happened through a different path? If yes, the rule targets a symptom, not the cause — dig deeper.

## Directory Structure

Auto-create directories as needed:

```
.jdi/
├── config.yaml              # Team config (git-tracked)
├── config.local.yaml        # Personal overrides (gitignored, user-created)
├── .gitignore               # Ignores config.local.yaml and runtime artifacts
├── status
├── workflows/
│   └── default.yaml
├── reports/{task_id}/
│   ├── orchestrator.md      # Human-readable workflow log (tail this!)
│   └── {step_name}.md
├── locks/{task_id}.lock
├── lessons_archive/
└── LESSONS.md
```

## Resources

- **references/workflow-schema.md**: Complete workflow YAML schema reference
- **assets/templates/jdi_template/**: Scaffolding template copied as `.jdi/` by `jdi init`
- **assets/sample-claude-code-task-management-skill.md**: Template for task-management skill (user must copy)
- **assets/sample-workflow.yaml**: Complete example workflow (plan → implement → review → finalize)
- **assets/just-do-it.sh**: Bash loop runner with configurable max iterations

## Bash Loop Usage

**Prerequisite:** The bash loop spawns a new `claude -p` session per iteration. Without a shared task list, each session starts with an empty task list and cannot track workflow state. Ensure `CLAUDE_CODE_TASK_LIST_ID` is set in `.claude/settings.json` before running the loop (this is done automatically by `/jdi init`).

Use `assets/just-do-it.sh` for production loop execution:

```bash
# Copy to project root
cp /path/to/just-do-it/assets/just-do-it.sh ./

# Run with defaults (max 10 iterations)
./just-do-it.sh

# Run with custom max iterations
./just-do-it.sh -m 50

# Run unlimited until WORKFLOW_COMPLETE/ABORT
./just-do-it.sh -m 0

# Run specific workflow and task
./just-do-it.sh -w code-review -t 123

# Stop after current task completes (don't continue to next)
./just-do-it.sh -s
```

Exit codes: `0` = WORKFLOW_COMPLETE (or STEP_COMPLETE with `-s`), `1` = ABORT, `2` = max iterations reached, `3` = HUMAN_REQUIRED

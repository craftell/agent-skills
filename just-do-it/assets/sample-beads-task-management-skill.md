---
name: task-management
description: Task management interface for just-do-it workflow orchestration using Beads (bd). Provides commands to get next task, get context, complete tasks, update tasks, and list all tasks. Required by just-do-it skill.
argument-hint: <next|context|complete|update|list> [options]
user-invocable: false
allowed-tools: Bash
---

# Task Management Skill (Beads Backend)

Task management operations for just-do-it workflow orchestration, backed by [Beads](https://github.com/steveyegge/beads) (`bd` CLI).

## Prerequisites

Beads must be initialized in the project (`bd init`). All `bd` commands use `--json` for agent-parseable output.

## Argument Parsing

The subcommand is `$0`. Parse `$ARGUMENTS` to extract command and options:

| Command | Usage | Description |
|---------|-------|-------------|
| `next` | `/task-management next` | Get next unblocked task |
| `context` | `/task-management context` | Get current task context |
| `complete` | `/task-management complete` | Mark current task as done |
| `update` | `/task-management update --feedback "text" --step "name"` | Update task |
| `list` | `/task-management list` | List all tasks |

For `update` command, parse flags from remaining arguments:
- `--feedback "text"`: Feedback to append to notes
- `--step "name"`: New step prefix for title

## Implementation Notes

This template uses the Beads `bd` CLI for task tracking. All commands should be executed via the Bash tool with `--json` for structured output. Adapt as needed for other backends (GitHub Issues, Linear, etc.).

### next

1. Run `bd ready --json` to get tasks with no open blockers
2. Pick the first task from the result (highest priority)
3. Run `bd update <id> --claim` to atomically set assignee and status to `in_progress`
4. Output the task title

If no tasks available, output: `NO_TASKS_AVAILABLE`

### context

1. Run `bd list --json` to find the current task with status `in_progress`
2. Run `bd show <id> --json` to retrieve full task details
3. Parse step prefix from title (e.g., `[review] Fix bug` → step is `review`)
4. Output in this format:

```markdown
## Current Task

**Title:** {title without prefix}
**Description:** {description}
**Current Step:** {step prefix or "none"}
```

If no in_progress task, output: `NO_CURRENT_TASK`

### complete

1. Run `bd list --json` to find the current `in_progress` task
2. Run `bd close <id> --reason "Completed by workflow"` to close the task
3. Output: `TASK_COMPLETED: {task title}`

### update

Parse arguments: `--feedback "text"` and `--step "step-name"`

1. Run `bd list --json` to find the current `in_progress` task
2. Run `bd show <id> --json` to get current details
3. If `--feedback` provided, run `bd update <id> --notes "text"` to append feedback
4. If `--step` provided, run `bd update <id> --title "[step-name] Original title"` to update the step prefix
5. Output: `TASK_UPDATED`

### list

1. Run `bd list --json` to get all tasks
2. Output each task in format: `{id}: [{status}] {title}`

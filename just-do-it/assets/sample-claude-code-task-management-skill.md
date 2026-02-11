---
name: task-management
description: Task management interface for just-do-it workflow orchestration. Provides commands to get next task, get context, complete tasks, update tasks, and list all tasks. Required by just-do-it skill.
argument-hint: <next|context|complete|update|list> [options]
user-invocable: false
allowed-tools: TaskList, TaskGet, TaskUpdate, TaskCreate
---

# Task Management Skill

Task management operations for just-do-it workflow orchestration.

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
- `--feedback "text"`: Feedback to append to description
- `--step "name"`: New step prefix for subject

## Implementation Notes

This template uses Claude Code's built-in TaskList/TaskGet/TaskUpdate tools. Adapt as needed for other backends (GitHub Issues, Linear, etc.).

### next

1. Use TaskList to get all tasks
2. Find first task with status `pending` that has no blockers
3. Use TaskUpdate to set status to `in_progress`
4. Output the task subject

If no tasks available or all blocked, output: `NO_TASKS_AVAILABLE`

### context

1. Use TaskList to find current `in_progress` task
2. Use TaskGet to retrieve full task details
3. Parse step prefix from subject (e.g., `[review] Fix bug` → step is `review`)
4. Output in this format:

```markdown
## Current Task

**Title:** {subject without prefix}
**Description:** {description}
**Current Step:** {step prefix or "none"}
```

If no in_progress task, output: `NO_CURRENT_TASK`

### complete

1. Use TaskList to find current `in_progress` task
2. Use TaskUpdate to set status to `completed`
3. Output: `TASK_COMPLETED: {task subject}`

### update

Parse arguments: `--feedback "text"` and `--step "step-name"`

1. Use TaskList to find current `in_progress` task
2. Use TaskGet to get current description
3. If `--feedback` provided, append to description
4. If `--step` provided, update subject prefix to `[step-name]`
5. Use TaskUpdate with new description and subject
6. Output: `TASK_UPDATED`

### list

1. Use TaskList to get all tasks
2. Output each task in format: `{id}: [{status}] {subject}`

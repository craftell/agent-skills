# Orchestrator Log Format Reference

Log file: `.jdi/reports/{task_id}/orchestrator.md`

## Preamble (once, via `Write`)

```markdown
# Workflow Log — {task_id}: {title}
Started: {YYYY-MM-DD HH:MM:SS} | Workflow: {name}

---
```

## Step Entry (appended via `Bash >>` heredoc)

```markdown
## [{HH:MM:SS}] {prev_step} → {next_step}

> {Summary from agent output}

---
```

## Variants

| Situation | Format |
|-----------|--------|
| First step | `→ {step}` |
| End | `{step} → DONE` |
| Error | `⚠ ABORT — {step}` |
| Paused | `⏸ PAUSED — {step}` |
| Done | `✓ COMPLETE` |

---
name: bead-cli
description: See ~/.claude/shared-rules/global/cli-skills.md
---

# Bead CLI Skill

All bead operations via the `bd` CLI. No MCP tool needed.

## Commands

| Operation | CLI | Notes |
|---|---|---|
| List open beads | `bd list -s open` | Run at every session start |
| List closed beads | `bd list -s closed` | |
| Show bead + comments | `bd show <id> && echo "--- COMMENTS ---" && bd comments <id>` | Two calls merged |
| Create bead | `bd --repo <project_path> create --title "<title>" --type task --description "<desc>"` | `create` uses `--repo`, not `--db` |
| Create with labels | `bd --repo <project_path> create --title "<title>" --type task --description "<desc>" --labels "knowledge"` | |
| Add comment | `bd comments add <id> "<text>"` | |
| Close bead | `bd close <id> --reason="<reason>"` | Reason must explain WHAT was done |

## Prerequisites

- `bd` CLI in PATH (installed with iterative-dev)
- Default repo: current working directory's `.beads/dolt`

## Non-Default Repo

All commands except `create` accept `--db <path>/.beads/dolt` for cross-project access:
```bash
bd --db /path/to/project/.beads/dolt list -s open
bd --db /path/to/project/.beads/dolt show <id>
bd --db /path/to/project/.beads/dolt comments add <id> "text"
```

## Examples

```bash
# Session start — list open beads
bd list -s open

# Show bead with full comment history
bd show Monitor_CC-abc && echo "--- COMMENTS ---" && bd comments Monitor_CC-abc

# Create a new work bead
bd --repo ~/Documents/ai/Monitor_CC create \
  --title "Fix proxy cache rebuild on tool growth" \
  --type task \
  --description "BP-layout v2 causes rebuild when new MCP tools injected. See decisions/cache_rebuild_cases.md"

# Add session-end STAND comment
bd comments add Monitor_CC-abc "STAND:
- DONE: Implemented BP-layout v2 (commit 060ff07)
- OPEN: Verify with live session
- APPROACH: Two-marker layout (anchor + end), stable position prevents byte-diff"

# Close resolved bead
bd close Monitor_CC-abc --reason="BP-layout v2 merged and verified in 3 sessions without rebuild"
```

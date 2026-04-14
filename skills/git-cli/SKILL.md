---
name: git-cli
description: See ~/.claude/shared-rules/global/cli-skills.md
---

# Git CLI Skill

Non-check git operations. Always use `git_check` (MCP) first — it auto-stages files and
produces the diff summary needed for the commit message.

## Commands

| Operation | CLI | Notes |
|---|---|---|
| Commit | `git -C <repo_path> commit -m "<message>"` | Use HEREDOC for multi-line (see below) |
| Push | `git -C <repo_path> push` | Falls back to `-u origin <branch>` if no upstream |
| Push with upstream | `git -C <repo_path> push -u origin $(git -C <repo_path> branch --show-current)` | For first push on new branch |
| Post-commit check | `git -C <repo_path> status --short` | Empty output = clean working tree |
| Plugin sync | `~/.claude/plugins/cache/brunowinter-plugins/iterative-dev/1.0.0/plugin-sync.sh <name> <repo_path>` | Plugin repos only (`.claude-plugin/plugin.json` must exist) |

## Commit Message Format

```bash
git -C <repo_path> commit -m "$(cat <<'EOF'
<type>: <description>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

Types: `feat` / `fix` / `refactor` / `docs` / `chore`. Max 72 chars on first line.

## Push Workflow

```bash
# Try plain push first
git -C <repo_path> push
# If "no upstream" error → set upstream
git -C <repo_path> push -u origin $(git -C <repo_path> branch --show-current)
```

## Post-Commit Verification

```bash
git -C <repo_path> status --short
# Empty output = CLEAN = proceed
# Non-empty = still dirty, stage and commit remaining files
```

Exception: `.beads/` entries in dirty output can be treated as clean (bead state, not code).

## Plugin Sync

Only run for plugin repos (repos that have `.claude-plugin/plugin.json`):

```bash
PLUGIN=~/.claude/plugins/cache/brunowinter-plugins/iterative-dev/1.0.0
$PLUGIN/plugin-sync.sh iterative-dev ~/Documents/ai/Meta/blank
```

After sync: kill old server process and `/mcp` to reconnect.

## Examples

```bash
PROJECT=~/Documents/ai/Monitor_CC

# Full commit + push cycle (after git_check)
git -C "$PROJECT" commit -m "$(cat <<'EOF'
fix: skip MCP injection for empty-tools requests

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"

git -C "$PROJECT" push

git -C "$PROJECT" status --short  # should be empty
```

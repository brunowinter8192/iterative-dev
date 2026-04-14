---
name: plugin-cli
description: See ~/.claude/shared-rules/global/cli-skills.md
---

# Plugin CLI Skill

Manages `<project>/.claude/active_plugins.json` — the file the Monitor_CC proxy reads to
decide which MCP tool schemas to inject into each request.

**This is separate from Claude Code's `enabledPlugins` in `settings.local.json`.**
`active_plugins.json` controls proxy-level schema injection. `enabledPlugins` controls
which plugins Claude Code loads as MCP servers.

## Prerequisites

- `jq` and `sponge` (from `moreutils`) in PATH
- File created automatically if missing (default: `{"plugins": ["iterative-dev"]}`)

## Commands

| Operation | CLI |
|---|---|
| List active plugins | `cat <project>/.claude/active_plugins.json` |
| Activate plugin | `jq '.plugins += ["<name>"] \| .plugins \|= unique' <project>/.claude/active_plugins.json \| sponge <project>/.claude/active_plugins.json` |
| Deactivate plugin | `jq '.plugins -= ["<name>"]' <project>/.claude/active_plugins.json \| sponge <project>/.claude/active_plugins.json` |
| Create default file | `mkdir -p <project>/.claude && echo '{"plugins": ["iterative-dev"]}' > <project>/.claude/active_plugins.json` |

## Default State

On proxy start, `claude_proxy_start.sh` resets this file to `{"plugins": ["iterative-dev"]}`.
Activations within a session are ephemeral — they do NOT persist to the next session.

`iterative-dev` is always present and cannot be removed (proxy enforces this).

## Examples

```bash
PROJECT=~/Documents/ai/Monitor_CC

# See what's active
cat "$PROJECT/.claude/active_plugins.json"
# → {"plugins": ["iterative-dev"]}

# Activate github-research for this session
jq '.plugins += ["github-research"] | .plugins |= unique' \
  "$PROJECT/.claude/active_plugins.json" | \
  sponge "$PROJECT/.claude/active_plugins.json"
# → {"plugins": ["iterative-dev", "github-research"]}

# Deactivate when done
jq '.plugins -= ["github-research"]' \
  "$PROJECT/.claude/active_plugins.json" | \
  sponge "$PROJECT/.claude/active_plugins.json"

# Reset to default (same as proxy does at start)
echo '{"plugins": ["iterative-dev"]}' > "$PROJECT/.claude/active_plugins.json"
```

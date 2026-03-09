# iterative-dev

Development workflow engine for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Provides a structured 5-phase development cycle, plugin development tooling, autonomous git operations, and worker spawning — all as a single installable plugin.

## Plugin Components

| Type | Name | Description |
|------|------|-------------|
| Skill | `iterative-dev` | 5-phase cycle (PLAN → IMPLEMENT → RECAP → IMPROVE → CLOSING), Beads cross-session context, plan files, code-investigate agent dispatch |
| Skill | `plugin-dev` | Plugin architecture (3-repo chain), plugin.json authoring, cache management, LSP plugins, distribution workflow |
| Skill | `agent-code-investigate` | Tool reference and behavioral guardrails for the code-investigate-specialist agent |
| Agent | `code-investigate-specialist` (Haiku) | Codebase exploration — returns FILE/LINES/RELEVANT blocks only |
| Agent | `git-committer` (Haiku) | Autonomous git staging, commit, push for multiple repos. Auto-detects plugin repos and runs plugin-sync |
| Command | `/spawn-worker` | Spawn isolated Claude session in a git worktree via tmux + Ghostty |

## Cross-Plugin Infrastructure

`src/pipeline/` provides utilities used by other plugins:

- **`jsonl_to_md.py`** — Converts Claude Code subagent JSONL session logs to Markdown (tool call details + summary). Used by the RAG plugin's eval workflow.
- **`list_agents.py`** — Lists subagent sessions for a project with agent type, timestamp, and size.

## Installation

```
/plugin marketplace add brunowinter8192/claude-plugins
/plugin install iterative-dev
```

## Repository

[brunowinter8192/Meta](https://github.com/brunowinter8192/Meta)

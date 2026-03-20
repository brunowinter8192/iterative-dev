# iterative-dev Plugin

Source repo for the `iterative-dev` plugin. Development workflow engine for Claude Code — structured development cycle, worker spawning, git automation, session analysis.

## Sources

See [sources/sources.md](sources/sources.md).

## Pipeline Components

| Component | Purpose | Key Files |
|---|---|---|
| Worker Spawning | tmux session management, Ghostty viewer, worker orchestration (list/capture/send) | `src/spawn/tmux_spawn.sh` |
| Git Automation | Three-phase git workflow for git-committer agent (pre-commit check, staging verification, post-commit status) | `src/git/check.py`, `src/git/staged.py`, `src/git/post.py` |
| Session Pipeline | JSONL session log analysis — conversion to Markdown, subagent listing, tool call extraction. Cross-plugin dependency (RAG eval) | `src/pipeline/jsonl_to_md.py`, `src/pipeline/list_agents.py`, `src/pipeline/extract_calls.py` |

### Key Files

- `plugin-sync.sh` — Deploys source repo to plugin cache (`~/.claude/plugins/cache/`)
- `.claude-plugin/plugin.json` — Plugin manifest (skills, agents, commands registration)

## Project Structure

```
.
├── CLAUDE.md
├── README.md
├── plugin-sync.sh
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── agents/
│   ├── code-investigate-specialist.md
│   └── git-committer.md
├── commands/
│   ├── eval-spawn.md
│   ├── docs-spawn.md
│   └── rules-check-spawn.md
├── skills/
│   ├── iterative-dev/
│   ├── recap/
│   ├── plugin-dev/
│   ├── worker-rules/
│   ├── eval-agent/
│   ├── doc-review/
│   ├── rules-check/
│   └── agent-code-investigate/
├── src/
│   ├── DOCS.md
│   ├── spawn/
│   │   └── tmux_spawn.sh
│   ├── git/
│   │   ├── DOCS.md
│   │   ├── check.py
│   │   ├── staged.py
│   │   └── post.py
│   └── pipeline/
│       ├── DOCS.md
│       ├── jsonl_to_md.py
│       ├── list_agents.py
│       └── extract_calls.py
├── decisions/
│   ├── spawn.md
│   ├── git.md
│   └── pipeline.md
├── sources/
│   └── sources.md
├── dev/
│   └── debug/
│       └── log_permission_request.sh
└── Hooks_Reference/          # External reference repos (Q1, Q2)
```

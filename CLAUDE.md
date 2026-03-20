# iterative-dev Plugin

Source repo for the `iterative-dev` plugin. Development workflow engine for Claude Code — structured development cycle, worker spawning, git automation, session analysis.

## Sources

See [sources/sources.md](sources/sources.md).

## Pipeline Components

### Worker Spawning

| Component | Implementation | Config |
|-----------|---------------|--------|
| **Session Management** | tmux new-session with direct command arg | remain-on-exit on |
| **Viewer** | Ghostty AppleScript (1.3+) / open -na (1.2.x) | — |
| **Orchestration** | worker_list, worker_status, worker_capture, worker_send | status via #{pane_dead} |

### Git Automation

| Component | Implementation | Config |
|-----------|---------------|--------|
| **Pre-Commit + Stage** | check.py --auto-stage | SKIP: .beads/, .DS_Store, .env, credentials, .claude/worktrees/ |
| **Staging Verification** | staged.py (fallback) | same SKIP_PATTERNS |
| **Post-Commit** | post.py | same SKIP_PATTERNS |

### Session Pipeline

| Component | Implementation | Config |
|-----------|---------------|--------|
| **JSONL to Markdown** | jsonl_to_md.py | --dispatch for main session context |
| **Subagent Listing** | list_agents.py | --session latest filter |
| **Tool Call Extraction** | extract_calls.py | --calls N,M selection |

### Key Files

| File | Component |
|------|-----------|
| `src/spawn/tmux_spawn.sh` | Worker Spawning |
| `src/git/check.py` | Git Automation (pre-commit + auto-stage) |
| `src/git/staged.py` | Git Automation (staging verification, fallback) |
| `src/git/post.py` | Git Automation (post-commit) |
| `src/pipeline/jsonl_to_md.py` | Session Pipeline (shared dependency) |
| `src/pipeline/list_agents.py` | Session Pipeline |
| `src/pipeline/extract_calls.py` | Session Pipeline |
| `plugin-sync.sh` | Plugin deployment |
| `.claude-plugin/plugin.json` | Plugin manifest |

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
├── src/                            → [DOCS.md](src/DOCS.md)
│   ├── spawn/
│   │   └── tmux_spawn.sh
│   ├── git/                        → [DOCS.md](src/git/DOCS.md)
│   │   ├── check.py
│   │   ├── staged.py
│   │   └── post.py
│   └── pipeline/                   → [DOCS.md](src/pipeline/DOCS.md)
│       ├── jsonl_to_md.py
│       ├── list_agents.py
│       └── extract_calls.py
├── decisions/                      → Pipeline decision records
│   ├── spawn.md
│   ├── git.md
│   └── pipeline.md
├── sources/
│   └── sources.md
├── dev/
│   ├── debug/
│   │   └── log_permission_request.sh
│   └── spawn/
│       ├── test_direct_command.sh
│       └── test_status_detection.sh
└── Hooks_Reference/                # External reference repos (Q1, Q2)
```

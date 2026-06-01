# iterative-dev Plugin

Source repo for the `iterative-dev` plugin. Development workflow engine for Claude Code — structured development cycle, worker spawning via CLI, git automation via CLI, session analysis.

## Pipeline Components

### Worker Spawning

| Component | Implementation | Config |
|-----------|---------------|--------|
| **Session Management** | tmux new-session with direct command arg | remain-on-exit on |
| **Viewer** | Ghostty AppleScript (1.3+) / open -na (1.2.x) | — |
| **CLI** | `worker-cli spawn/send/list/status/capture/merge/kill` | `~/.local/bin/worker-cli` → `bin/worker-cli` |

### Git Automation

| Component | Implementation | Config |
|-----------|---------------|--------|
| **Pre-Commit + Stage** | check.py --auto-stage | SKIP: .beads/, .DS_Store, .env, credentials, .claude/worktrees/ |
| **Staging Verification** | staged.py | same SKIP_PATTERNS |
| **Post-Commit** | post.py | same SKIP_PATTERNS |
| **CLI** | `git-check`, `dev-sync`, `gc` | `~/.local/bin/` → `bin/` |

### Session Pipeline

| Component | Implementation | Config |
|-----------|---------------|--------|
| **JSONL to Markdown** | jsonl_to_md.py | --dispatch for main session context |
| **Subagent Listing** | list_agents.py | --session latest filter |
| **Tool Call Extraction** | extract_calls.py | --calls N,M selection |

### Key Files

| File | Component |
|------|-----------|
| `src/spawn/tmux_spawn.sh` | Worker Spawning — bash library |
| `src/spawn/spawn.py` | Worker Spawning — worktree setup + launch |
| `src/git/check.py` | Git Automation — pre-commit + auto-stage |
| `src/git/staged.py` | Git Automation — staging verification |
| `src/git/post.py` | Git Automation — post-commit |
| `src/pipeline/jsonl_to_md.py` | Session Pipeline |
| `src/pipeline/list_agents.py` | Session Pipeline |
| `src/pipeline/extract_calls.py` | Session Pipeline |
| `bin/worker-cli` | Worker CLI wrapper (symlinked to `~/.local/bin/`) |
| `bin/dev-sync` | Dev→main fast-forward CLI (symlinked to `~/.local/bin/`) |
| `bin/git-check` | Pre-commit check CLI (symlinked to `~/.local/bin/`) |
| `bin/gc` | Git commit shortcut (symlinked to `~/.local/bin/`) |
| `bin/plugin-publish` | One-step plugin push + cache-sync + version-bump (symlinked to `~/.local/bin/`) |
| `plugin-sync.sh` | Low-level plugin cache rsync (used internally; prefer `plugin-publish`) |
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
├── bin/
│   ├── gc                          → ~/.local/bin/gc
│   ├── worker-cli                  → ~/.local/bin/worker-cli
│   ├── dev-sync                    → ~/.local/bin/dev-sync
│   ├── git-check                   → ~/.local/bin/git-check
│   └── plugin-publish              → ~/.local/bin/plugin-publish
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
│   ├── rule-consolidation/
│   └── tool-use/
├── src/                            → [DOCS.md](src/DOCS.md)
│   ├── spawn/                      → [DOCS.md](src/spawn/DOCS.md)
│   │   ├── tmux_spawn.sh
│   │   └── spawn.py
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
└── dev/                            → [DOCS.md](dev/DOCS.md)
    ├── debug/
    │   └── log_permission_request.sh
    ├── pipeline/                   → [DOCS.md](dev/pipeline/DOCS.md)
    │   └── audit_error_patterns.py
    └── spawn/
        ├── test_direct_command.sh
        └── test_status_detection.sh
```

# iterative-dev

Development workflow engine for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — structured 5-phase development cycle, worker spawning with git isolation, and autonomous git operations as a single installable plugin.

## Features

- **5-phase development cycle** — PLAN → IMPLEMENT → RECAP → IMPROVE → CLOSING with Beads for cross-session context
- **Worker spawning** — isolated Claude sessions in git worktrees via tmux + Ghostty, with automatic branch management
- **Worker lifecycle management** — spawn, monitor, send follow-up tasks, merge, and kill workers with full context continuity
- **Autonomous git operations** — staging, commit, and push across multiple repos with auto-detected plugin sync
- **Cross-session context** — Beads system stores decisions, open items, and session narratives between sessions
- **Codebase exploration** — Haiku-powered investigation agent returns file locations and code findings
- **Plugin development tooling** — 3-repo chain architecture, plugin.json authoring, cache management, distribution workflow
- **Documentation review** — structured audit of project documentation with automated worker dispatch

## Quick Start

```bash
/plugin marketplace add brunowinter8192/claude-plugins
/plugin install iterative-dev
```

Then in any project session, activate the development cycle:

```
/iterative-dev
```

## Prerequisites

- Claude Code CLI
- tmux + [Ghostty](https://ghostty.org/) (for worker spawning)

## Setup

Plugin install handles everything automatically. No additional setup required.

## Usage

### Skills & Commands

| Name | Type | Description |
|------|------|-------------|
| `/iterative-dev` | Skill | Activates the 5-phase development cycle (PLAN → IMPLEMENT → RECAP → IMPROVE → CLOSING) |
| `/iterative-dev:rule-consolidation` | Skill | Rule consolidation and cleanup workflow |
| `/iterative-dev:tool-use` | Skill | Tool-call hygiene — token efficiency, per-tool behavior reference, CLI wrappers |
| `/iterative-dev:recap` | Skill | Session recap and bead closing workflow |
| `/eval-spawn` | Command | Spawn an eval agent session |
| `/docs-spawn` | Command | Spawn a documentation review worker |
| `/rules-check-spawn` | Command | Spawn a rules compliance check worker |

### CLI Wrappers

All worker and git operations are available as CLI commands in `~/.local/bin/`:

| Command | Description |
|---------|-------------|
| `worker-cli spawn <name> <prompt> <project> [model]` | Spawn worker in git worktree |
| `worker-cli send <name> <message> [project]` | Send message to running worker |
| `worker-cli list <project>` | List active workers with status |
| `worker-cli status <name> <project>` | Check worker status (idle/working/exited) |
| `worker-cli capture <name> <project>` | Capture pane output to file |
| `worker-cli merge <name> <project>` | Merge worker branch |
| `worker-cli kill <name> <project>` | Kill session + remove worktree + delete branch |
| `git-check [repo]` | Pre-commit check + auto-staging |
| `dev-sync [project]` | Fast-forward main to dev HEAD (no checkout) |
| `gc "<message>"` | Stage tracked modifications + commit |

### Agents

| Agent | Model | Description |
|-------|-------|-------------|
| `code-investigate-specialist` | Haiku | Codebase exploration — finds files, traces pipelines, returns FILE/LINES/RELEVANT blocks |
| `git-committer` | Haiku | Autonomous git staging, commit, push for one or more repos. Auto-detects plugin repos and runs plugin-sync |

## Workflows

### Development Cycle

Activate `/iterative-dev` at the start of a session. The skill walks through five phases:

1. **PLAN** — scope the session, read beads, create a plan file, design worker strategy
2. **IMPLEMENT** — spawn workers for implementation tasks, monitor progress, merge results
3. **RECAP** — review what was done, verify features live, kill workers after approval
4. **IMPROVE** — route process improvements to the right automation files
5. **CLOSING** — write bead STAND block, commit, close resolved beads

### Worker Lifecycle

Workers are isolated Claude sessions in git worktrees. The lifecycle:

1. **Spawn** — orchestrator writes a prompt file, calls `worker-cli spawn` → new tmux session + Ghostty window opens
2. **Implement** — worker reads prompt, executes task, commits to its branch
3. **Monitor** — orchestrator checks `worker-cli status`, uses `worker-cli capture` to read output
4. **Follow-up** — send corrections or additional tasks via `worker-cli send` (worker retains full context)
5. **Merge** — `worker-cli merge` merges the branch into dev; worker stays alive for verification
6. **Kill** — after user verification, `worker-cli kill` removes the tmux session, worktree, and branch

Workers stay alive until the feature is verified. The tmux session preserves context for bug fixes via `worker-cli send`.

## Troubleshooting

<details>
<summary>Worker appears stuck — no output in Ghostty window</summary>

Check if the worker is waiting for input:

```bash
tmux capture-pane -t worker-<project>-<name> -p | tail -20
```

If the Claude Code prompt is visible (idle state), send a message via `worker-cli send`. If the session is completely unresponsive, kill and re-spawn:

```bash
worker-cli kill <name> <project>
```

Then re-spawn with a new prompt file.

</details>

## License

MIT

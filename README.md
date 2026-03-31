# iterative-dev

Development workflow engine for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — structured 5-phase development cycle, worker spawning with git isolation, and autonomous git operations as a single installable plugin.

## Features

- **5-phase development cycle** — PLAN → IMPLEMENT → RECAP → IMPROVE → CLOSING with Beads for cross-session context
- **Worker spawning** — isolated Claude sessions in git worktrees via tmux + Ghostty, with automatic branch management
- **Worker lifecycle management** — spawn, monitor, send follow-up tasks, merge, and kill workers with full context continuity
- **Autonomous git operations** — staging, commit, and push across multiple repos with auto-detected plugin sync
- **Cross-session context** — Beads system stores decisions, open items, and session narratives between sessions
- **Codebase exploration** — Haiku-powered investigation agent returns file locations and code findings
- **LLM proxy** — send prompts to external models (NVIDIA NIM, default Mistral Large 675B) from within a session
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
- Python 3.10+ (for the MCP server)
- tmux + [Ghostty](https://ghostty.org/) (for worker spawning)
- `NVIDIA_API_KEY` in `.env` — optional, only required for the `prompt` MCP tool

## Setup

Plugin install handles the MCP server automatically. For the `prompt` tool, add your API key:

```bash
echo "NVIDIA_API_KEY=your_key_here" >> .env
```

Get a free NVIDIA NIM API key at [build.nvidia.com](https://build.nvidia.com). The free tier supports 40 requests/min.

## Usage

### Skills & Commands

| Name | Type | Description |
|------|------|-------------|
| `/iterative-dev` | Skill | Activates the 5-phase development cycle (PLAN → IMPLEMENT → RECAP → IMPROVE → CLOSING) |
| `/iterative-dev:plugin-dev` | Skill | Plugin architecture, plugin.json authoring, cache management, distribution workflow |
| `/iterative-dev:worker-rules` | Skill | Mandatory rules for workers running in git worktrees — run as first action in every worker session |
| `/iterative-dev:agent-code-investigate` | Skill | Tool reference and behavioral guardrails for the code-investigate-specialist agent |
| `/iterative-dev:eval-agent` | Skill | Eval workflow for session and agent evaluation |
| `/iterative-dev:doc-review` | Skill | Documentation review and gap analysis with automated worker dispatch |
| `/eval-spawn` | Command | Spawn an eval agent session |
| `/docs-spawn` | Command | Spawn a documentation review worker |
| `/rules-check-spawn` | Command | Spawn a rules compliance check worker |

### MCP Tools

| Tool | Description | Example prompt |
|------|-------------|----------------|
| `prompt` | Send a prompt to an external LLM (NVIDIA NIM) and return the response | "Use the prompt tool to ask Mistral to summarize this code" |
| `eval_list_agents` | List subagents for a project session with type, timestamp, size, and JSONL paths | "List agents from the latest session" |
| `eval_extract` | Convert agent JSONL to summary, or extract specific tool calls by number | "Extract tool calls 1, 3, 7 from this agent session" |

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

1. **Spawn** — orchestrator writes a prompt file, calls `worker_spawn` → new tmux session + Ghostty window opens
2. **Implement** — worker reads prompt, executes task, commits to its branch
3. **Monitor** — orchestrator checks `worker_status`, uses `worker_capture(tail=30)` to read output
4. **Follow-up** — send corrections or additional tasks via `worker_send` (worker retains full context)
5. **Merge** — `worker_merge` merges the branch into main; worker stays alive for verification
6. **Kill** — after user verification, `worker_kill` removes the tmux session, worktree, and branch

Workers stay alive until the feature is verified. The tmux session preserves context for bug fixes via `worker_send`.

## Troubleshooting

<details>
<summary>Worker appears stuck — no output in Ghostty window</summary>

Check if the worker is waiting for input:

```bash
tmux capture-pane -t worker-<project>-<name> -p | tail -20
```

If the Claude Code prompt is visible (idle state), send a message via `worker_send`. If the session is completely unresponsive, kill and re-spawn:

```bash
tmux kill-session -t worker-<project>-<name>
```

Then use `worker_kill` to clean up the worktree and branch before re-spawning.

</details>

<details>
<summary>MCP server connection lost — "No such tool available"</summary>

The MCP server process crashed. Run `/mcp` in Claude Code to reconnect. If reconnect fails, check the server process:

```bash
ps aux | grep "iterative-dev.*server.py" | grep -v grep
```

If no process is found, the server will restart automatically on the next `/mcp`. If it keeps crashing, check `mcp-start.sh` for startup errors and verify Python dependencies are installed.

</details>

<details>
<summary>prompt tool returns "ERROR: NVIDIA_API_KEY not set"</summary>

Add your NVIDIA NIM API key to `.env` in the project root:

```bash
echo "NVIDIA_API_KEY=your_key_here" >> .env
```

Then restart the MCP server (`/mcp`) so the new environment variable is picked up. The key must be present when the server process starts — changing `.env` after startup has no effect until restart.

</details>

## License

MIT

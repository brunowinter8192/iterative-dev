# Sources

| Source | Stars | Type | Coverage | Decision |
|---|---|---|---|---|
| [Claude Code Docs](https://docs.anthropic.com/en/docs/claude-code) | — | Official Docs | Hooks API, Subagents, Slash Commands, Plugin System | all |
| [anthropics/claude-code](https://github.com/anthropics/claude-code) | 80k | Upstream | Issues for upstream bugs, feature requests (inject, worktrees) | all |
| [anthropics/claude-code#24947](https://github.com/anthropics/claude-code/issues/24947) | — | Issue | `claude inject` — programmatic input to running sessions. OPEN, high-priority. Blocks worker→main notification. | spawn |
| [anthropics/claude-code#15553](https://github.com/anthropics/claude-code/issues/15553) | — | Issue | Programmatic Input Submission in Interactive Mode. OPEN. Confirms: CC ignores programmatic stdin as submit. | spawn |
| [njbrake/agent-of-empires](https://github.com/njbrake/agent-of-empires) | 1.2k | GitHub Repo | tmux + worktree session manager (Rust). Shell-ready via direct command arg to `new-session`. Status via `#{pane_dead}` + `#{pane_current_command}`. | spawn |
| [craigsc/cmux](https://github.com/craigsc/cmux) | 379 | GitHub Repo | Shell-based worktree lifecycle for Claude Code. Ephemeral worktrees, `cmux rm` cleanup. Community validates tmux+worktree pattern. | spawn |
| [gavraz/recon](https://github.com/gavraz/recon) | 112 | GitHub Repo | tmux-native dashboard for monitoring Claude Code agents (Rust + Ratatui). Status detection via tmux queries. | spawn |
| [nielsgroen/claude-tmux](https://github.com/nielsgroen/claude-tmux) | 71 | GitHub Repo | tmux popup with session management + worktree support (Rust). Status detection via `capture-pane` content analysis. | spawn |
| [Martian-Engineering/maniple](https://github.com/Martian-Engineering/maniple) | 37 | GitHub Repo | MCP server for orchestrating Claude Code/Codex sessions via iTerm2 or tmux (Python). First inspiration for MCP-based worker orchestration. | spawn |

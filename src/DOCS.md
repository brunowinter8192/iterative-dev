# src/

Source modules for the iterative-dev plugin infrastructure.

## Documentation Tree

- [git/DOCS.md](git/DOCS.md) — Git automation utilities (pre-commit, staging, post-commit)
- [pipeline/DOCS.md](pipeline/DOCS.md) — Session JSONL analysis (conversion, listing, extraction)

## tmux_spawn.sh

**Purpose:** Worker spawning and orchestration via tmux + Ghostty.
**Input:** Worker name, project path, model, task prompt.
**Output:** tmux session with running Claude Code instance, Ghostty viewer window.

Located in `spawn/` (single-file directory).

# src/

## Role

Implementation packages behind the iterative-dev commands in `bin/`: worker spawning and CLI subcommands, git helpers, session analysis, poread, docs drift check. Touch via the subdirectory that owns the concern. Do not put code directly in `src/`.

## Public Interface

`__init__.py` is empty. Each subdirectory is entered through its own package or shell library, see its DOCS.md.

## Flow

A `bin/` command delegates into exactly one subdirectory: `bin/worker-cli` into `worker_cli/` and `spawn/`, the git tools into `git/`, and the launchers into `poread_cli/` and `docs_drift_check/`. `pipeline/` has no launcher.

## Modules

None. `src/` holds only subdirectories:

- `spawn/` — worker spawning, status detection, pane I/O, proxy setup, revive (shell libs plus `spawn.py`); see `spawn/DOCS.md`.
- `worker_cli/` — `worker-cli` subcommand implementations; see `worker_cli/DOCS.md`.
- `git/` — pre-commit check, commit, staging and post-commit verification; see `git/DOCS.md`.
- `pipeline/` — session JSONL conversion, agent listing, tool-call extraction; see `pipeline/DOCS.md`.
- `poread_cli/` — poread CLI, marker-minting half; see `poread_cli/DOCS.md`.
- `docs_drift_check/` — DOCS.md rule checker; see `docs_drift_check/DOCS.md`.

## State

None. `logs/` holds runtime log output of the worker tooling and is not part of the source.

# src/common/

## Role

Shell helpers shared by more than one command: project-root resolution, project-directory encoding for Claude Code session paths, worker session naming. Touch when one of these rules changes. Do not add command logic here.

## Public Interface

No `__init__.py`. `paths.sh` is sourced by `bin/worker-cli`, `bin/dev-sync`, `bin/git-check` and `src/spawn/tmux_spawn.sh`, each locating it relative to its own real path.

## Flow

A path or worker name in → resolved project root, encoded session directory name or tmux session name out (stdout).

## Modules

### paths.sh (41 LOC)

**Purpose:** Single owner of project-root resolution, Claude Code project-directory encoding and the worker session naming rule.
**Reads:** current directory, filesystem (for the project root).
**Writes:** stdout only.
**Called by:** `bin/worker-cli` (through `src/worker_cli/`), `bin/dev-sync`, `bin/git-check`, `src/spawn/tmux_spawn.sh` (and through it every spawn lib).
**Calls out:** none.

## State

None.

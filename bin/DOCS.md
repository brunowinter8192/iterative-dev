# bin/

## Role

Command-line entry points of the iterative-dev plugin: worker lifecycle, git commit helpers, plugin publishing, docs drift check, file display. Touch when adding or changing a user-facing command. Do not touch for command internals: the Python and shell implementations live in `src/`.

## Public Interface

No `__init__.py`. Each executable is invoked by name from PATH: the plugin's `bin/` directory is on PATH inside Claude Code, and some tools are additionally symlinked into `~/.local/bin`. The exposed commands are the module names below.

## Flow

Command line in → thin wrapper resolves the project path or plugin root → delegates to `src/` (Python via `python3 -m`, shell libs via `source`) or runs a short self-contained script → stdout and exit code out.

## Modules

### dev-sync (38 LOC)

**Purpose:** Fast-forward main or master to the dev branch HEAD via a ref update, without checkout.
**Reads:** git repository at the given or current project path (worktree-aware).
**Writes:** the main/master branch ref; stdout.
**Called by:** users and agents on PATH.
**Calls out:** git.

---

### docs-drift-check (7 LOC)

**Purpose:** Launcher that exports the current directory as project root and runs the docs-drift-check CLI from the plugin directory.
**Reads:** plugin root environment variable, current directory.
**Writes:** stdout and exit code of `src/docs_drift_check`.
**Called by:** users and agents on PATH; `~/.local/bin/docs-drift-check`.
**Calls out:** python3, `src/docs_drift_check`.

---

### gc (17 LOC)

**Purpose:** Git commit shortcut: commits tracked modifications, or stages the listed files first.
**Reads:** git working tree.
**Writes:** git index, git commit.
**Called by:** users on PATH.
**Calls out:** git.

---

### gcommit (29 LOC)

**Purpose:** Stage everything except the skip list and commit, worktree-correct; refuses to commit into the plugin directory.
**Reads:** plugin root environment variable, target repository path.
**Writes:** git index, git commit, stdout.
**Called by:** agents and users on PATH.
**Calls out:** python3, `src/git/commit.py`.

---

### git-check (7 LOC)

**Purpose:** Pre-commit report with auto-staging for a repository, resolving worktree paths to the project root.
**Reads:** git repository at the given or current path.
**Writes:** git index (auto-stage), stdout report.
**Called by:** agents and users on PATH.
**Calls out:** python3, `src/git/check.py`.

---

### plugin-publish (228 LOC)

**Purpose:** Push a plugin source repo, bump the cached version and rsync it into the plugin cache, updating the installed-plugins registry atomically.
**Reads:** plugin source repo, `installed_plugins.json`.
**Writes:** plugin cache directory, `installed_plugins.json` plus a backup in `/tmp`, git remote.
**Called by:** users on PATH; `~/.local/bin/plugin-publish`.
**Calls out:** git, rsync, python3.

---

### poread (5 LOC)

**Purpose:** Launcher for the poread CLI, which exports a file's full content past Bash's inline-output ceiling.
**Reads:** plugin root environment variable.
**Writes:** stdout and exit code of `src/poread_cli`.
**Called by:** agents on PATH; `~/.local/bin/poread`.
**Calls out:** python3, `src/poread_cli`.

---

### show (46 LOC)

**Purpose:** Open files in the default macOS app: text formats in CotEditor, PDFs via a read-only copy, everything else via `open`.
**Reads:** the named files.
**Writes:** read-only PDF copies under the temp dir; opens GUI apps; stdout.
**Called by:** users and agents on PATH.
**Calls out:** macOS `open`, CotEditor.

---

### worker-cli (63 LOC)

**Purpose:** Dispatcher for the worker lifecycle subcommands; loads implementations from `src/worker_cli/` next to the script and spawn libs from the plugin cache.
**Reads:** worker registry directory, plugin root environment variable.
**Writes:** stdout and exit codes; delegates all state changes to the libs.
**Called by:** agents and users on PATH; `~/.local/bin/worker-cli`; `skills/iterative-dev-duallog`.
**Calls out:** tmux, git, `src/worker_cli/`, `src/spawn/`.

## State

None. Every command is stateless between invocations except through the files and repositories it operates on.

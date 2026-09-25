# dev/worker_cli/

## Role

Test for the argument tripwire of worker-cli: every removed or surplus argument must abort with a clear error that shows the correct form. Touch when changing a subcommand's form.

## Public Interface

No `__init__.py`; run manually: `bash dev/worker_cli/test_arg_tripwire.sh`.

## Flow

Parallel strands call the real `bin/worker-cli` with old-style calls (project path, model, wait path) and with missing arguments, and assert exit code and stderr text.

## Modules

### test_arg_tripwire.sh (86 LOC)

**Purpose:** Asserts exit 2 and the correct-form message for every removed project_path or model argument, and for missing arguments.
**Reads:** Nothing persistent.
**Writes:** stdout.
**Called by:** Run manually.
**Calls out:** `bin/worker-cli` (subprocess), `dev/strand_runner.sh`.

## State

Each strand owns a private scratch directory (home, logs, registry, its own tmux server); nothing is shared between strands or with the real user state.

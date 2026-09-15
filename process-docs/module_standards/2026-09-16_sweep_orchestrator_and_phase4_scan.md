# Refactor sweep, orchestrator record and the Phase 4 control-flow scan (2026-09-16)

Orchestrator half of an `iterative-dev-refactor` run over this whole project — the plugin running
the skill was swept with the skill. Phases 1 to 3 were executed and merged. Phase 4 was scanned and
deliberately NOT acted on — the list at the bottom is the handover.

The worker's own entries are `2026-09-16_comment_and_docs_conformance.md` and
`2026-09-16_docs_drift_zero.md` in this same folder. This entry holds what only the orchestrator saw.

## Starting state, measured

21 Python modules, 2872 lines, the smallest of the four projects in this sweep. Two modules over the
400-LOC ceiling and five functions at or above the 50-LOC ceiling, none at or above 100.

- `dev/desktop_targeting/probe.py` 454 LOC
- `src/pipeline/jsonl_to_md.py` 437 LOC
- `dev/model_selector/verify_spawn_model_resolution.py::verify_spawn_model_resolution_workflow` 65
- `src/spawn/_capture_clean.py::_clean` 60
- `dev/desktop_targeting/probe.py::main` 57
- `dev/worker_spawn/test_capture_clean.py::_assert_cases` 55
- `dev/session_pipeline/audit_error_patterns.py::format_report` 53

After Phase 1: 28 modules, 3030 lines, zero over 400, largest at 248, zero functions at or above 50.

`jsonl_to_md.py` split into `jsonl_parse.py`, `dispatch_context.py` and `markdown_format.py`, with
the entry module reduced to a 43-LOC orchestrator plus its CLI block. `probe.py` split into
`objc_bridge.py`, `spaces.py`, `window_probe.py` and `move_test.py`, following the section dividers
the original author had already written into the file.

## The compatibility shim that was proposed and refused

The worker proposed keeping `jsonl_to_md.py` re-exporting all 24 of its original public names, so
that `extract_calls.py` and `list_agents.py` would keep working unchanged. The stated reason was
that `process-docs/session_pipeline/jsonl_analysis_2026-03.md` mentions the RAG plugin's eval
workflow using this module, and that the risk of an unknown external caller justified the insurance.

That was refused, and the basis for refusing it is worth recording because the same question will
come back. `jsonl_to_md` was grepped across the plugin cache at
`~/.claude/plugins/cache/brunowinter-plugins/`, across `~/.claude/scripts`, across `~/.local/bin`,
and across every sibling project under `Documents/ai/Meta/ClaudeCode/cli/`. The only hits outside
this repository were inside the plugin cache's own copy of this same repository. There is no
external caller. A re-export shim would have been a second import path for every symbol, with no
observed failure behind it, keeping a 24-name public surface alive that nothing consumes.

The two in-repo callers were re-pointed at the new modules instead. The import graph now tells the
truth.

## The one place where deleting a docstring would have changed behaviour

`dev/desktop_targeting/probe.py` passed its module docstring to argparse as `description=__doc__`.
Deleting it would have silently emptied the `--help` output. The text was moved verbatim into a
`_HELP_TEXT` constant and `--help` was verified byte-identical. Grep for `__doc__` before any
comment purge.

## Phase 2, the comment purge, in numbers

185 hits across 21 files: 167 comments and 18 docstrings. 155 were deleted as already covered by the
owning `DOCS.md` or by an existing process-docs entry, 29 carried substance that existed nowhere
else and were relocated verbatim, and one was the `__doc__` case above.

Nine `DOCS.md` were rewritten to the Role / Public Interface / Flow / Modules / State format, all
nine cross-checked so the stated LOC equals the real `wc -l`.

## Phase 3, and the prior I got wrong

Every `DOCS.md` was already under the 400-line split threshold, the largest at 105 lines. But
`docs-drift-check` reported 21 findings here, by far the worst of the four projects, and it also
reported that this project had no `.drift-whitelist.txt` at all, so every symbol finding came
through unfiltered.

I handed the worker my reading that the six path findings were probably dead references. That was
wrong, and the worker proved it. All three missing files —`src/proxy/inject_poread.py`,
`src/constants.py`, `dev/proxy/poread_inject_tests.py` — exist right now in the monitor-cc
repository, exactly where the surrounding prose already said they were. The docs were correct. The
checker only looks inside backticks and never learns that a path belongs to another repository. The
fix was to move the checker's own supported cross-repo marker inside the backticks, as
`` `src/proxy/inject_poread.py (Monitor_CC)` ``.

The one genuine path finding was `.git/hooks/pre-commit` in `src/git/DOCS.md`, which never exists as
a literal file — it is a runtime-built path into whatever target repository `check.py` is pointed
at. It was reworded as prose rather than presented as a project file.

All 15 symbol findings were false positives, and all for one root cause: `docs-drift-check` greps
only `src/**/*.py` and `dev/**/*.py`, while a large part of this project's real logic lives in shell.
`worker_capture_clean`, `go_quiet`, `kill_claude_child`, `delete_hook_entry`,
`WORKER_REGISTRY_DIR`, `WORKER_LOGGER_DIR`, `CLAUDE_PLUGIN_ROOT`, `SAW_WORKING`, `NAMES` and
`CHATTY` are all real bash functions and variables in `bin/worker-cli`, `src/spawn/tmux_spawn.sh`
and `dev/worker_wait/test_worker_wait.sh`. `TMUX_TMPDIR` is an external tmux variable, `EXIT` is
bash's trap pseudo-signal, `CONFLICT` is git's own merge output, `XXXXXXXX` is `mktemp` placeholder
text, and `THIS` is an ordinary English word caught by a backtick-pairing artifact.

`.drift-whitelist.txt` now exists, grouped by root cause. Final drift state is zero.

## A DOCS.md judgement worth keeping

`src/DOCS.md` and `dev/DOCS.md` hold no `.py` modules of their own; they are navigation maps over
their subdirectories. They were left with their Directory Map and Areas sections rather than being
forced into the module format, because a Modules section there would be empty and the map is what
actually serves a reader. A directory with no modules is not a module directory.

## Phase 4 candidate list, scanned and not classified

An AST pass over every `except` handler, classified by what the handler does. Eight handlers produce
output, one has a body of only `pass`, two of only `continue`.

The ones that most need a decision:

- `src/spawn/spawn.py:123`, `_resolve_worker_model`, `except Exception: worker = ""` followed by
  `return worker or _DEFAULT_WORKER_MODEL`. A config file that exists but is malformed produces
  exactly the same result as a config file that is absent: the default model, silently. Anyone who
  mistypes their worker model config gets the default and is never told.
- `src/pipeline/list_agents.py:24`, `list_agents_workflow`, `except (RuntimeError, FileNotFoundError)`
  logs a warning and then appends a synthetic agent record with `agent_type` set to
  `'UNKNOWN (parse error)'`. This one is close to being a legitimate second path, because the record
  it produces names the path that produced it — which is one of the four conditions the standard
  requires. Worth reviewing against the other three.
- `src/spawn/spawn.py:93` and `:95`, `tmux_spawn`, return the strings
  `"ERROR: tmux spawn timed out after 60s"` and `"ERROR: <strerror>"`. These are error strings
  returned as normal output, which the caller then has to string-match to detect.
- `src/poread_cli/__main__.py:38`, `:51` and `:74`, in `_check_size`, `_read_file` and the module
  level `except BrokenPipeError`.
- `src/pipeline/markdown_format.py`, `format_timestamp`, `except (ValueError, TypeError)`.
- `src/pipeline/jsonl_parse.py:22`, `load_jsonl`, `except json.JSONDecodeError: continue` — a
  malformed line in a session JSONL is skipped without a trace. Given that this function is the
  entry to every other pipeline module, a silently dropped line silently shortens every downstream
  count.
- `dev/session_pipeline/audit_error_patterns.py:74` and `:77`, the same shape in dev.

## Method notes for a successor

Main scanned, workers fixed. Every number above came from an AST walk run at orchestration level.

For the comment purge, AST equality is the proof: parse before and after, strip docstrings from both
trees, compare the dumps. 20 of 21 files in this project were AST-identical, and the single
exception was the disclosed `__doc__` case.

`dev/desktop_targeting/` cannot be exercised without real macOS window-manager access and it opens
and closes TextEdit windows. Do not run the full probe to produce evidence. `probe.py --help`
exercises every `ctypes.CDLL` load and the whole argparse wiring, and exits before touching
TextEdit; `spaces.choose_target_space` can be run read-only against the live Space state. Both were
used here and both were compared old against new.

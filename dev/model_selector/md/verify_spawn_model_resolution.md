# spawn.py model-resolution verification — 2026-09-25T15:39:47

spawn: /var/folders/t2/_8msw65s0glfkr10g1mp_4g40000gn/T/tmpv_zwg1di/does_not_exist.json not found, using default worker model claude-sonnet-5
Missing config file -> 'claude-sonnet-5' (expected hardcoded fallback)
Valid config -> 'claude-fable-5' (expected config's worker model)
Malformed JSON -> aborts with JSONDecodeError: Expecting property name enclosed in double quotes: line 1 column 2 (char 1) (expected abort, no fallback)
spawn: no worker model in /var/folders/t2/_8msw65s0glfkr10g1mp_4g40000gn/T/tmpcms6mefn/missing_key.json, using default worker model claude-sonnet-5
Config missing 'worker' key -> 'claude-sonnet-5' (expected hardcoded fallback)

## argparse (real parser)
usage: spawn.py [-h] [--no-worktree] name prompt_file project_path
spawn.py: error: unrecognized arguments: claude-explicit-cli-arg
Fourth positional (model) given to the real parser -> exit 2 (expected rejection, no model argument exists)
Real parser without model -> hasattr(args, 'model')=False (expected False)
Resolved model -> 'claude-fable-5' (expected config's worker model)

RESULT: PASS — _resolve_worker_model correct for valid/missing/missing-key config, aborts on a malformed config; the real parser accepts no model argument, so the model always comes from the config and is a concrete non-empty string.

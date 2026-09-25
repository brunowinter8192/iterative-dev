# spawn.py model-resolution verification — 2026-09-25T03:22:50

spawn: /var/folders/t2/_8msw65s0glfkr10g1mp_4g40000gn/T/tmpee01d0h3/does_not_exist.json not found, using default worker model claude-sonnet-5
Missing config file -> 'claude-sonnet-5' (expected hardcoded fallback)
Valid config -> 'claude-fable-5' (expected config's worker model)
Malformed JSON -> aborts with JSONDecodeError: Expecting property name enclosed in double quotes: line 1 column 2 (char 1) (expected abort, no fallback)
spawn: no worker model in /var/folders/t2/_8msw65s0glfkr10g1mp_4g40000gn/T/tmpwdaewnow/missing_key.json, using default worker model claude-sonnet-5
Config missing 'worker' key -> 'claude-sonnet-5' (expected hardcoded fallback)

## argparse resolution (real parser, default=None)
Explicit CLI arg given -> resolved_model='claude-explicit-cli-arg' (expected explicit arg, config never consulted)
CLI arg omitted -> args.model=None (expected None, not the string 'None')
CLI arg omitted -> resolved_model='claude-fable-5' (expected config's worker model, never the literal 'None')

RESULT: PASS — _resolve_worker_model correct for valid/missing/missing-key config, aborts on a malformed config; args.model is real None (never the string 'None') when omitted; the resolved model passed onward is always a concrete non-empty string.

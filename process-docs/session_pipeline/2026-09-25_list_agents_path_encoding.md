# list_agents: Claude Code project directory encoding

## Problem

`src/pipeline/list_agents.py` (`derive_cc_project_dir`) encoded the project path by replacing only `/` with `-`. Claude Code also replaces `.` and `_` with `-`. Every worktree path contains `/.claude/`, so `--project <worktree path>` raised "CC project directory not found".

Observed encoding: `/Users/brunowinter2000/Documents/ai/monitor-cc/.claude/worktrees/itdevcore` maps to `~/.claude/projects/-Users-brunowinter2000-Documents-ai-monitor-cc--claude-worktrees-itdevcore` (exists on disk). The shell side had the same bug earlier (`encode_worktree_path` in `src/common/paths.sh`; see area `worker_spawn`).

## Fix

New function `encode_project_path` in `list_agents.py` replaces `/`, `.` and `_` with `-`; `derive_cc_project_dir` calls it. Other special characters were never observed, so no fallback exists; the existing `FileNotFoundError` is the tripwire. The encoding is only used in this module, so it is not in a shared config.

## Test

`dev/session_pipeline/test_list_agents_encoding.py`: builds a fake HOME under /tmp with `.claude/projects/<encoded>/` for project `<tmp>/home/my_proj/.claude/worktrees/wt_a`, containing a main session (Agent tool_use plus progress anchor) and `<sid>/subagents/agent-abc123.jsonl`. It runs `python3 -m src.pipeline.list_agents` with HOME overridden (dev scripts may not import from src/). Old code: FileNotFoundError with `...home-my_proj-.claude-worktrees-wt_a`. New code: PASS.

## Verification (2026-09-25)

No directory under `~/.claude/projects` (323 entries) contains any `*/subagents/agent-*.jsonl` (`find` returned nothing), so the real-directory verification could not be run. Nothing was created there.

## Pitfall

zsh prints "no matches found" per glob miss; in loops over `~/.claude/projects` append `2>/dev/null` or the output becomes huge.

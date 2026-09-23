# gcommit: relative repo_path and plugin-dir guard (2026-09-23)

## Incident
`gcommit "<msg>" .` run from /Users/brunowinter2000/Documents/ai/canvas committed 75 unrelated files into
~/.claude/plugins/cache/brunowinter-plugins/iterative-dev/1.0.0 (a git repo of its own), not into canvas.

## Cause
bin/gcommit did `REPO="${2:-$(pwd)}"` and then `cd "$PLUGIN" && python3 -m src.git.commit "$MESSAGE" "$REPO"`.
The `cd` happened before the path was used, so a relative `.` resolved to the plugin dir.
(commit.py calls os.path.abspath, but by then cwd is already the plugin dir.)

## Fix (bin/gcommit)
- The repo path is resolved to a physical absolute path with `cd "$REPO_INPUT" && pwd -P` in the caller's cwd,
  BEFORE the cd into the plugin dir. Nonexistent path: abort, exit 1.
- Guard: if the resolved repo equals the plugin dir or lies below it, abort with exit 1 and a message. The plugin
  dir is `CLAUDE_PLUGIN_ROOT` or the cache default, also resolved with `pwd -P`.

## Tests (scratch repo /tmp/gc/r)
- `gcommit msg .` from repo root: committed in scratch repo.
- `gcommit msg ..` from repo/sub: committed in scratch repo.
- absolute path, and no argument: committed in scratch repo.
- From inside the plugin dir (`.` and no arg), and with `/plugin/src`: refused, rc=1, plugin repo untouched.
- `/nonexist`: refused, rc=1.

## Testing gotcha
A global commit-msg hook requires author name "Bruno Winter" and email brunowinter8192@github.com. Scratch repos
need GIT_AUTHOR_*/GIT_COMMITTER_* env vars with those values; do not modify git config (a tool hook blocks that).

# Bracketed-paste fix for worker message delivery (2026-09-23)

Follows on from `2026-09-23_paste_breaks_on_cc_280.md` in this same area — read that
first for the original symptom and the options considered. This entry covers the
fix that was actually applied (option 1 from that doc, by user decision), the test
harness built to verify it, and pitfalls hit while building that harness.

## Fix

Both text-delivery paths into a worker pane are in `src/spawn/tmux_spawn.sh`:
`worker_send()` and `spawn_claude_worker()`'s prompt inject. Both did
`tmux paste-buffer -d -t <pane>` (no `-p`). Changed both to
`tmux paste-buffer -d -p -t <pane>` (bracketed paste). Nothing else in either
function changed. `worker_revive()` was checked and does not inject text into a
pane at all — it passes `--resume '<session_id>'` as a CLI arg to the runner
script, so it needed no change.

The `<pasted_content id="...">` wrapper CC now adds to every bracketed paste
(confirmed live, see below) is explicitly out of scope per the user's decision —
that's the monitor-cc proxy's job, not this fix's.

## Enter-submit timing: kept the static `sleep 0.2`, with numbers

Measured paste-to-render latency directly (paste-buffer -p, then poll
`capture-pane` every 10ms until the pane shows the rendered content/placeholder,
without ever sending Enter) across all four message sizes from the original bug
doc, 3 samples each, across four separate full script runs (so ~12 samples per
size class in total across runs):

- Consistently 22-46ms across short (13 chars), 800+ char single line, 18-line
  (~1470 char), and 9000-char multiline — no size-dependent trend, no sample ever
  came close to the 200ms sleep.
- `tmux paste-buffer` writes synchronously to the pty before the command returns
  (confirmed by these numbers: the "latency" measured is purely CC's own render
  time, and it's the same order of magnitude regardless of payload size).

Conclusion: the existing fixed `sleep 0.2` has a ~4-9x margin over observed render
time at every size tested. Not worth replacing with a poll-based readiness check —
that would add a new failure/timeout surface for a margin this wide. If a future
CC version's render time ever grows close to 200ms, the dev script
(`dev/worker_message_delivery/probe_bracketed_paste.sh`) reproduces this
measurement and should be rerun before touching the sleep value.

## What delivery looks like now, live-observed

Short message, no wrapper at all — `message.content` in the JSONL is the plain
string, byte-identical to the input:
```
"hello short test 12345"
```

18-line / ~1470-char message, wrapped:
```
"\n\n<pasted_content id=\"a3db\">\nThis is filler line number 01...\n</pasted_content id=\"a3db\">\n"
```
The wrapper appears once CC's own paste heuristics decide to collapse the
paste — happened for the 800+ char single line too (character-count threshold,
not just line-count), consistent with the "800 characters OR two lines" rule
from the original bug doc.

## Old method (no `-p`), re-confirmed broken — but not always the same way

Ran the pre-fix `paste-buffer -d -t` (no `-p`) once per script run, same 18-line
message every time. It "submitted" in the sense that a `type=="user"` JSONL entry
always appeared (unlike the very first live incident, where Enter did nothing at
all) — but the content was wrong in two different ways across separate runs of
this same script:
- Run A: reordered/duplicated — the closing marker landed mid-line-18, splitting
  it, with the tail fragment (`multiline paste test.`) appearing a second time
  OUTSIDE the wrapper, after it.
- Run B: severely truncated — the delivered content was just `multiline paste
  test.` (21 characters), i.e. only the last few words of an 18-line, ~1470-
  character message arrived. This is the same failure shape as the original
  live incident (`t you think is wrong`, `ntly, since bars sit ...`) — the head
  of the message lost.

Both are "old method, no `-p`" on the exact same CC binary and message; the
variance itself is the point — this method is non-deterministic, not just
occasionally slow. The fixed method (`-p`) delivered the full, uncorrupted
message on every one of 4 script runs (16/16 individual case deliveries) with
no variance beyond the expected leading `\n\n` from the wrapper.

## Building the dev harness: two pitfalls, both about tmux session lifecycle

`dev/worker_message_delivery/probe_bracketed_paste.sh` boots real `claude-280`
processes in throwaway tmux sessions. Two issues came up that have nothing to do
with the paste fix itself and would bite anyone writing a similar harness:

1. **Always set `remain-on-exit on` on throwaway sessions, even in a disposable
   test script.** Without it, if `claude-280` exits early for any reason, tmux
   kills the whole session immediately and the polling loop just sees an empty/
   absent pane — indistinguishable from "still booting". This showed up as
   spurious "setup FAILED (no input-ready state within 25s)" on 3 of 5 cases in
   one run, timed out at the full 25s each time, even though — once
   `remain-on-exit on` was added and the same boot sequence was run standalone —
   every boot actually reached the input-ready `❯` prompt in 1-2 seconds. The
   fix was cosmetic risk-elimination, not a real slow-boot problem: it makes a
   real crash visible (`tmux has-session` still true, pane content shows the
   crash) instead of hiding it behind a generic timeout label.

2. **CC writes an async post-turn artifact (an auto-generated conversation title,
   `{"type":"ai-title",...}`) a moment after the turn is already visible in the
   JSONL — this write can race a `tmux kill-session` issued right after
   verification.** Observed live: `rm -rf` on the project's `~/.claude/projects/
   <encoded>` dir would occasionally leave a one-line orphan directory behind,
   containing only the `ai-title` record (no `type=="user"` entry at all) — the
   session had already been killed and its scratch dir removed, but this file
   reappeared a few hundred ms later. It was most visible on whichever case ran
   last in a given script invocation, because the top-level `trap cleanup EXIT`
   safety net has the least elapsed time to also lose that same race for the
   final case. Fix: `cleanup_case()` sleeps 1.5s after `tmux kill-session`
   before `rm -rf`-ing the scratch dir and the project JSONL dir. Confirmed
   clean (zero tmux sessions, zero scratch dirs, zero project dirs left behind)
   across 3 consecutive full runs after this fix.

Neither of these is a paste-delivery concern — flagging them here so nobody
re-debugges the same two things while extending this harness.

## Verification method used in the harness

Each of the 5 cases boots its own fresh `claude-280` session (fresh git-init'd
scratch dir, so no conversation history exists yet), so "exactly one
`type=="user"` JSONL entry, whose de-wrapped text matches the input" is a
sufficient completeness check — no need to distinguish it from a prior turn.
`_verify_user_message.py` strips the `<pasted_content id="...">...</pasted_content
id="...">` wrapper via regex before comparing, and compares with `.strip()` (the
wrapper leaves a harmless leading `\n\n` that isn't a content defect — see the
"What delivery looks like now" section above).

## Files changed

- `src/spawn/tmux_spawn.sh` — `-p` added to both `paste-buffer` calls; one-line
  comment above each updated to name the bracketed-paste reasoning.
- `src/spawn/DOCS.md` — LOC count corrected (848 -> 912; the 848 was already
  stale before this change, not something this change alone caused).
- `dev/worker_message_delivery/probe_bracketed_paste.sh`,
  `dev/worker_message_delivery/_verify_user_message.py`,
  `dev/worker_message_delivery/DOCS.md` — new.
- `dev/worker_message_delivery/md/probe_bracketed_paste_report.md` — generated
  by the script, reflects whichever run happened last (this file documents the
  cross-run variance the single latest report can't show).

## Recap checkpoint

`git diff integration --name-only` against this branch listed exactly the 8
files above (`dev/DOCS.md`, `dev/worker_message_delivery/DOCS.md`,
`dev/worker_message_delivery/_verify_user_message.py`,
`dev/worker_message_delivery/md/probe_bracketed_paste_report.md`,
`dev/worker_message_delivery/probe_bracketed_paste.sh`, this file,
`src/spawn/DOCS.md`, `src/spawn/tmux_spawn.sh`) — no drift between what was
implemented and what's staged. Both touched DOCS.md files (`dev/DOCS.md` for
the new area's index entry, `src/spawn/DOCS.md` for the corrected LOC count)
were already updated as part of the main task commit, so the recap needed no
further DOCS.md changes — only this addendum.

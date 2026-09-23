# Worker messages arrive mangled or unsent on CC 2.1.280 (2026-09-23)

Area `worker_message_delivery` builds on `worker_spawn` (prompt injection via paste, since
2026-05-30) in this repo and on `cc_version_pin` in monitor-cc (version bumps).

## Symptom, observed live on 2026-09-23

A canvas-project worker (`statusbar`) spawned at 11:14 UTC, the first spawns after the worker
binary pin moved to `claude-280` (commit `314ee70`, 09:37 UTC same day; previous worker pin in
`tmux_spawn.sh` was `claude-223`, the user's mains ran `claude-258`).

Read from the worker's own session JSONL:

- Spawn prompt, about 9,000 characters, multi-line: the worker received one user message of
  20 characters, `t you think is wrong` (the last words of the prompt). Everything before was lost.
- A `worker-cli send` of about 1,500 characters over several lines: text stayed in the input box,
  never submitted. The box started mid-sentence (`ntly, since bars sit ...`), the head was lost.
  A later short send appended to it and its Enter submitted the remaining 545 characters.
- Short single-line sends (173 characters) arrived complete and were submitted every time.

Knock-on effect: `worker-cli wait` only exits after it has seen the worker `working` once
(transition gate, 2026-09-02). An unsent message means the worker never starts, so the wait
keeps running until something aborts it. The wait itself behaved as designed; the user agreed
the only defect is message delivery.

## Mechanism in the code

`worker_send` and the spawn inject in `src/spawn/tmux_spawn.sh` both do:
`tmux load-buffer -` → `tmux paste-buffer -d -t <pane>` (no `-p`) → `sleep 0.2` →
`tmux send-keys Enter`. Without `-p`, tmux does not wrap the text in bracketed-paste markers,
so Claude Code receives a burst of keystrokes and has to guess that it is a paste.

## Research on 2026-09-23

- Claude Code docs (quoted in anthropics/claude-code issue 86803): any paste over 800 characters
  or over two lines collapses to a `[Pasted text #N]` placeholder. Long-standing behavior.
- Issue 86803: since 2.1.224 a collapsed paste is routed differently on submit.
- Issue 85187: a message visible in the input box but never delivered, Enter does nothing
  (Remote Control path, 2.1.226). Same visible failure shape.
- Release notes 2.1.259 to 2.1.280 (indexed into `github_releases`): no entry about terminal
  paste detection. 2.1.267: "keystrokes no longer occasionally wait a frame behind spinner or
  streaming repaints", an input-handling change that may have altered unbracketed paste
  guessing. Hypothesis only, not confirmed.

## Probe on 2026-09-23, CC 2.1.280, same 1,472-character 18-line message

Two throwaway tmux sessions in a scratch git dir, run by the orchestrator, then deleted.

- A, the current method (no `-p`, 0.2 s, Enter): after the paste the text was in the input box
  in full and the footer said `paste again to expand`. After Enter the turn did NOT start, and
  the input box now began mid-line (`is filler text for ...`, lines 01 to 13 gone).
  Reproduces the live symptom exactly.
- B, bracketed paste (`tmux paste-buffer -p`, otherwise identical): the input showed
  `[Pasted text #1 +17 lines]`, Enter submitted, the turn ran, all 18 lines arrived.

Side effect found in B: CC 2.1.280 records a bracketed paste in the transcript wrapped as
`<pasted_content id="...">...</pasted_content>`. The model then treats it as pasted data, not
as the user's own instruction. In the probe it refused the embedded instruction ("Reply with
only the word OK") and asked what to do with the text, stating the instruction was part of the
pasted text. A worker whose whole task prompt arrives this way may therefore not act on it.

## Options as of 2026-09-23

1. Bracketed paste (`-p`) for every send and spawn: full delivery, but the whole message is
   marked as pasted content, with the instruction-following risk above.
2. File pointer: write any long message to a file, deliver only one short single line
   (under 800 characters, no newline), e.g. "Read <file> completely and follow it". Short
   single lines were delivered reliably on 2.1.280 in live use. Costs the worker one Read.
3. Short typed instruction line plus a bracketed paste of the body. Untested.

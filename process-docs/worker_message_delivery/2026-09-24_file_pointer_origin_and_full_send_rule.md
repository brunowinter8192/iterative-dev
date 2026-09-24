# Where the "Read <file> completely and follow it" sends came from (2026-09-24)

Continues this area after the 2026-09-23 bracketed-paste fix. On 2026-09-24 the user saw a monitor-cc main still sending worker tasks as a one-line pointer, e.g. `worker-cli send gapturn "Read /tmp/task-gapturn-continue-msgs.md completely and follow it."`, although full-length sends had worked since the fix.

## Finding

- No rule in `~/.claude/shared-rules` and nothing in `worker-cli` told a main to send file pointers. The only `/tmp` instruction in the rules is the spawn prompt file for `worker-cli spawn`.
- The wording is option 2 of the 2026-09-23 options list in this area ("File pointer: write any long message to a file, deliver only one short single line ... e.g. 'Read <file> completely and follow it'"). That option was NOT chosen; bracketed paste was.
- The canvas main (session `7f97cf69`) used option 2 as a stop-gap from 2026-09-23 11:15 UTC while sends were broken, and kept using it for the rest of the day, also after the fix: 17 pointer sends up to 17:11 UTC.
- The monitor-cc main of 2026-09-24 (session `07af087e`, started 09:15 UTC) read duallog output of those canvas workers at 09:15 and 09:32 UTC. The output listed their first user messages, e.g. `Read /tmp/task-statusbar.md completely and follow it exactly. It is your full task from the orchestrator...`. From 09:40 UTC it sent every long task that way itself (8 times until 13:40 UTC), while short messages still went directly. This is inferred from the order of events; the main's reasoning is not in the transcript.
- A scan over all main-session transcripts on this machine also found the pattern in a trading main on 2026-09-08, for spawn prompt files.

## Rule added

`shared-rules/main/workers.md`, § Interaktion mit Workern, user's wording (commit `84e37d5` in shared-rules):

```
**Sende per `send` immer den vollständigen Prompt.**
- Schreibe deinen Prompt nicht in Dateien und verweise darauf.
    - Gib dem Worker den Prompt komplett per `send`.
```

The practical form for a prepared text file is `worker-cli send <name> "$(cat <file>)"`.

## Size test

2026-09-24, CC 2.1.280 worker, bracketed-paste `worker_send`: a 502-line, 56,834-character text with quotes, backticks, backslashes and `$HOME`, a marker word in line 347 and two control questions at the end, sent with `worker-cli send flicker "$(cat /tmp/send-probe-large.txt)"`.

- The worker's transcript contained the source text verbatim (every character).
- The first API call failed with `ERR_PROXY_TUNNEL` ("the proxy refused the tunnel"). The worker's mitmdump was alive and reachable. The user had switched Wi-Fi at that moment; after reconnecting, the worker answered `347 500`, both correct. The error was the network, not the message size.

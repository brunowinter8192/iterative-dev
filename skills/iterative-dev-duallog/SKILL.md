---
name: iterative-dev-duallog
description: 
---

# Dual-Log Reading — Skill

Run via `duallog <command>` (in PATH). Every clock is LOCAL time.

## Units

**A session is one CC process, named by its log stem.**
- `api_requests_worker_<sid8>_<name>_<epoch>` for a worker, `api_requests_opus_<project>_<epoch>` for a main session.
- Any unambiguous substring of the stem selects it, usually the worker name.

**A REQ is one API request.**
- Numbered like the proxy pane's `#n`; re-fires collapse into their owner.

**A msg is one entry of the API messages array.**
- A role plus typed blocks, indexed from 0.

## Commands

| Command | Args | Output |
|---|---|---|
| sessions | [context] [--since D] [--until D] | table START / CONTEXT / SESSION, newest first |
| turns | session [N] | one line per turn: duration split into model time and tool time; with N, one line per request of turn N |
| reqs | [scope] [--since D] [--until D] [--main \| --worker] [--gap MIN] [--merged] [--rebuild] [--drop] | `REQ n  HH:MM:SS` per request, per session, with optional tails |
| msgs | session [from] [to] \| --req F [T] | one classifier line per msg, grouped under `── REQ n ──` separators |
| expand | session msg [--before N] [--after N] [--only classifier] | full block content of one msg and its window |
| search | term [scope] [--since D] [--until D] [--only classifier] [--case-sensitive] | `#msg role type chars` per hit, per session |

**context and scope are substrings.**
- `context` (sessions) matches the CONTEXT column; `scope` (reqs, search) matches CONTEXT or stem.
- `D` is `YYYY-MM-DD`, inclusive.

## sessions

```
START                CONTEXT                       SESSION
2026-09-06 22:27:49  worker/trading/reldist-power  api_requests_worker_1dda1c81_reldist-power_1788726467
2026-09-06 14:47:46  worker/trading/k-ratio        api_requests_worker_1dda1c81_k-ratio_1788698865
2026-09-06 10:10:25  opus/trading                  api_requests_opus_trading_1788682222
```

**CONTEXT tells main from worker.**
- `opus/<project>` is a main session, `worker/<project>/<worker-name>` a worker.

## turns

```
turn 1   22:27:49    41m27s  model   20m23s  tool   21m04s   77 reqs    102,389 tok  You are a WORKER.
turn 2   23:10:14     1m04s  model    1m03s  tool       0s    2 reqs      5,115 tok  recap
```

**A turn runs from one typed prompt to the model's idle text reply.**
- The prompt comes from the human, or from the orchestrator via `worker-cli send`.
- Pauses BETWEEN turns belong to no turn.
- Clock is the send time of the first request; duration ends at the last request's stream end.

**model and tool split the duration.**
- `model` sums generation time (send → stream end) over the turn's requests.
- `tool` sums the time between one stream end and the next send, i.e. tool execution plus hooks.
- `tok` sums output tokens; with `model` it tells thinking-heavy from output-heavy turns.
- `?` means the transcript join failed for that turn; clock and request count are always real.

**Read the split before drilling down.**
- `tool` near `model` → shell commands drove the turn.
- `model` dominant with high `tok` → generation drove it.

**turns <session> N breaks turn N down per request.**

```
REQ 24  22:36:15  model    3m56s  tool       0s     30,097 tok  Write
REQ 42  22:43:38  model       5s  tool    9m42s        193 tok  Bash
REQ 77  23:09:03  model      12s  tool        ?        973 tok
```

- `model`, `tool` and `tok` are this request's own values.
- The names at the end are the tool_use calls in its reply, empty for a text-only reply.
- The turn's last request shows `?` for tool time by design.
- The command behind a slow `tool` sits under the NEXT request's separator: `msgs <session> --req N+1`, then `expand` that msg.

## reqs

```
session api_requests_worker_1dda1c81_k-ratio_1788698865
REQ 46  14:58:19
REQ 47  18:02:18  +183m
```

**Plain reqs prints every request; each flag adds a filter or a tail, and they combine.**

**--gap MIN keeps the two requests bracketing a pause of at least MIN whole minutes.**
- The later one carries `+Nm`; the example above is `--gap 60`.
- A session with no qualifying pause prints only its `session` line.

**--merged interleaves every session in scope into one chronological chain.**

```
merged 2 sessions
REQ 46  14:58:19  k-ratio
REQ 47  18:02:18  k-ratio  +183m
```

- Each line is tagged with its worker or project.
- Use it with `--gap` for cache health: the prompt cache is shared by all workers of a project, so only a pause with NO request from ANY of them counts.

**--rebuild keeps requests where the cache write exceeded the cache read (CC > CR).**

```
REQ 3   14:47:54  CR 23,882  CC 34,029
REQ 47  18:02:18  CR 0  CC 152,851
```

- `CR` is cache_read_input_tokens, `CC` is cache_creation_input_tokens of that request.
- A hit means the prefix had to be rebuilt.

**--drop keeps requests that read back less than the previous request had cached.**

```
REQ 47  18:02:18  CR 0  CC 152,851  −149,746
```

- The condition is `CR(n) < CR(n-1) + CC(n-1)`; the tail is the shortfall.
- REQ 47 read 0 tokens from cache although ~150k were cached before: the cache expired during the 183-minute pause.
- The predecessor is always the same session's previous request, also under `--merged`.

**--main / --worker keep only opus/ or worker/ sessions.**

## msgs

```
── REQ 2  22:27:58  CR 13,267  CC 7,006 ──
[  2] assi  3 blocks              460c
        thinking                  149c
        tool_use[Read]            157c
        tool_use[Bash]            154c
[  3] user  2 blocks            14,886c
        tool_result             14,490c
        tool_result               396c
[  4] syst  system                 86c  −86 +1 → 1c
```

**The separator names the request that ADDED the msgs below it.**
- Msgs under REQ 2 are the reply to REQ 1 plus the tool results REQ 2 then sent.

**One line per msg, one sub-line per block.**
- `[i] role type chars`; `tool_use[Name]` carries the tool name.
- A tail `−N +M → Wc` means the proxy stripped N chars, injected M, and W went on the wire.
- Lines starting with `sys[i]` / `tool[Name]` directly under a separator are system blocks and tool definitions that request changed.

**Select by REQ or by msg index.**
- `msgs <s> --req 77 78` shows exactly the msgs of those requests.
- `msgs <s> 228 233` selects by msg index.

## expand

```
▶ ═══ msg #231 23:10:14 user 5 chars, 1 block(s) ═══
── block 0  text  5 chars ──
recap
```

**One header per msg, then every block's raw content.**
- A block the proxy changed is followed by `── stripped by REQ n ──` / `── injected by REQ n ──` sections.
- `--before` / `--after` widen the window; `--only user/text` keeps only matching msgs.

## search

```
term      "recap"  (case-insensitive)

session   api_requests_worker_1dda1c81_reldist-power_1788726467
#231  user      text  5c
```

**One line per matching block: msg index, role, block type, original chars.**
- Feed the index into `expand` or `msgs`.
- Scope is optional; omitted, every session is searched.

## Classifiers

**--only takes a role, a block type, or a role/type pair.**
- Forms: `user`, `tool_result`, `user/text`.
- A msg is selected when its role matches and ANY block matches the type, and it always shows ALL its blocks.

| Block type | What it is |
|---|---|
| text | Visible prose — the human's typed message under role user, the agent's reply under role assistant |
| thinking | The agent's internal reasoning |
| tool_use | A tool invocation: tool name plus input JSON — the executed command lives here |
| tool_result | The tool's output, returned under role user; `tool_result!err` marks errors |
| image | An embedded image |
| system | Runtime-injected block, e.g. token counters or deferred-tool lists |
| system-reminder | CC-injected context wrapped as a user msg (CLAUDE.md contents, env context) |
| task-notification | Background-task wake-up (task id, output path, status) — automated, never real user input |

## Reading rules

**A turn opener is a user msg with a text block and no tool_result block.**
- `system-reminder` and `task-notification` msgs never open a turn.

**The final text reply of a turn is only visible in the NEXT request's delta.**
- The first request of turn N+1 lists turn N's closing reply under its separator.

**Time inside a request cannot be split further.**
- The proxy records send time and first-byte time only; stream end comes from CC's transcript.

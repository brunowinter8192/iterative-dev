---
name: iterative-dev-duallog
description: 
---

# Dual-Log Reading — Skill

Run via `duallog <command>` (in PATH). Every clock is LOCAL time.

## Commands

### sessions

#### Input args

`sessions [context] [--since D] [--until D]`

- `context` — substring of the CONTEXT column, e.g. `trading` or `reldist-power`; omitted lists every session.
- `--since D` / `--until D` — start day, `YYYY-MM-DD`, inclusive.

#### Output

```
START                CONTEXT                       SESSION
2026-09-06 22:27:49  worker/trading/reldist-power  api_requests_worker_1dda1c81_reldist-power_1788726467
2026-09-06 14:47:46  worker/trading/k-ratio        api_requests_worker_1dda1c81_k-ratio_1788698865
2026-09-06 10:10:25  opus/trading                  api_requests_opus_trading_1788682222

3 sessions
```

- One row per session, newest first, then a count line.
- `START` — local time of the first request.
- `CONTEXT` — `opus/<project>` for a main session, `worker/<project>/<worker-name>` for a worker.
- `SESSION` — the stem; any unambiguous substring of it is the `session` argument of turns, msgs and expand.

### turns

#### Input args

`turns <session> [N]`

- `session` — unambiguous substring of a stem, e.g. `reldist-power`; two matches exit with an error, so add more of the stem, e.g. `reldist-power_1788`.
- `N` — a turn number from the bare listing; given, the output switches to one line per request of that turn.

#### Output

```
turn 1   22:27:49    41m27s  model   20m23s  tool   21m04s   77 reqs    102,389 tok  You are a WORKER.
turn 2   23:10:14     1m04s  model    1m03s  tool       0s    2 reqs      5,115 tok  recap
```

- One line per turn. A turn runs from one typed prompt (human, or orchestrator via `worker-cli send`) to the model's idle text reply; pauses between turns belong to no turn.
- clock — send time of the turn's first request.
- duration — that send to the stream end of the turn's last request.
- `model` — summed generation time (send → stream end) over the turn's requests.
- `tool` — summed time between one stream end and the next send, i.e. tool execution plus hooks.
- `reqs` — request count.
- `tok` — summed output tokens.
- trailing text — first line of the prompt that opened the turn.
- `?` — the transcript join failed for that turn; clock and `reqs` are always real.
- `tool` near `model` → shell commands drove the turn; `model` dominant with high `tok` → generation drove it.

With `N`:

```
REQ 24  22:36:15  model    3m56s  tool       0s     30,097 tok  Write
REQ 42  22:43:38  model       5s  tool    9m42s        193 tok  Bash
REQ 77  23:09:03  model      12s  tool        ?        973 tok
```

- One line per request of turn N, same REQ numbers as reqs and msgs.
- `model`, `tool`, `tok` — this request's own values.
- trailing names — the tool_use calls in this request's reply, empty for a text-only reply.
- The turn's last request shows `?` for `tool` by design.
- The command behind a slow `tool` sits under the NEXT request's separator: `msgs <session> --req N+1`, then `expand` that msg.

### reqs

#### Input args

`reqs [scope] [--since D] [--until D] [--main | --worker] [--gap MIN] [--merged] [--rebuild] [--drop]`

- `scope` — substring of CONTEXT or stem; omitted covers every session.
- `--since D` / `--until D` — start day, `YYYY-MM-DD`, inclusive.
- `--main` / `--worker` — keep only `opus/` or `worker/` sessions.
- `--gap MIN` — keep only the two requests bracketing a pause of at least MIN whole minutes.
- `--merged` — one chronological chain across every session in scope instead of one listing per session.
- `--rebuild` — keep only requests where the cache write exceeded the cache read.
- `--drop` — keep only requests that read back less than the previous request had cached.
- The flags combine.

#### Output

```
session api_requests_worker_1dda1c81_k-ratio_1788698865
REQ 1   14:47:46
REQ 2   14:47:50
```

- One `session` line, then one line per request: REQ number and send clock.

With `--gap 60`:

```
session api_requests_worker_1dda1c81_k-ratio_1788698865
REQ 46  14:58:19
REQ 47  18:02:18  +183m
```

- `+Nm` — minutes since the previous printed request.
- A session with no qualifying pause prints only its `session` line.

With `--merged --gap 60`:

```
merged 2 sessions
REQ 46  14:58:19  k-ratio
REQ 47  18:02:18  k-ratio  +183m
```

- Each line carries its worker or project as tag.
- This is the cache-health view: the prompt cache is shared by all workers of a project, so only a pause with NO request from ANY of them counts.

With `--rebuild`:

```
REQ 3   14:47:54  CR 23,882  CC 34,029
REQ 47  18:02:18  CR 0  CC 152,851
```

- `CR` — cache_read_input_tokens, `CC` — cache_creation_input_tokens of that request.
- Printed when `CC > CR`, i.e. the prefix had to be rebuilt.

With `--drop`:

```
REQ 47  18:02:18  CR 0  CC 152,851  −149,746
```

- Printed when `CR(n) < CR(n-1) + CC(n-1)`; the tail is the shortfall.
- Here REQ 47 read 0 tokens from cache although ~150k were cached before: the cache expired during the 183-minute pause.
- The predecessor is always the same session's previous request, also under `--merged`.

### msgs

#### Input args

`msgs <session> [from] [to]` or `msgs <session> --req F [T]`

- `session` — as in turns.
- `from` / `to` — inclusive msg indices; omitted prints the whole session.
- `--req F [T]` — inclusive REQ range instead; `T` defaults to `F`. Not combinable with `from`/`to`.

#### Output

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

- Separator — the request that ADDED the msgs below it, with its send clock and, when resolvable, CR/CC. Msgs under REQ 2 are the reply to REQ 1 plus the tool results REQ 2 then sent.
- `[i] role type chars` — one line per msg; a multi-block msg lists one indented sub-line per block.
- `tool_use[Name]` — the tool name; the command itself is in the block, see expand.
- `−N +M → Wc` — the proxy stripped N chars, injected M, and W went on the wire.
- `sys[i]` / `tool[Name]` lines directly under a separator — system blocks and tool definitions that request changed.

### expand

#### Input args

`expand <session> <msg> [--before N] [--after N] [--only classifier]`

- `session` — as in turns.
- `msg` — a msg index from msgs or search.
- `--before N` / `--after N` — widen the window by N msgs on either side.
- `--only classifier` — keep only msgs matching a role (`user`), a block type (`tool_result`), or both (`user/text`); a msg matches when its role matches and ANY block matches the type, and it always shows ALL its blocks.

#### Output

```
▶ ═══ msg #231 23:10:14 user 5 chars, 1 block(s) ═══
── block 0  text  5 chars ──
recap
```

- One header per msg with index, clock, role, size, block count; `▶` marks the anchor.
- One `── block i ──` header per block, then the raw content.
- `── stripped by REQ n ──` / `── injected by REQ n ──` — follow a block the proxy changed, showing what it removed and what it put there.

### search

#### Input args

`search <term> [scope] [--since D] [--until D] [--only classifier] [--case-sensitive]`

- `term` — literal substring, no regex; case-insensitive unless `--case-sensitive`.
- `scope` — substring of CONTEXT or stem; omitted searches every session.
- `--since D` / `--until D` — start day, `YYYY-MM-DD`, inclusive.
- `--only classifier` — as in expand.

#### Output

```
term      "recap"  (case-insensitive)

session   api_requests_worker_1dda1c81_reldist-power_1788726467
#231  user      text  5c
```

- One `session` line per session with hits, then one line per matching block: msg index, role, block type, original chars.
- Each block is reported once, however often the term occurs in it.
- Feed the index into expand or msgs.

## Block types

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

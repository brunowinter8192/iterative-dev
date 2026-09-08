---
name: iterative-dev-duallog
description: 
---

# Dual-Log Reading — Skill

Run via `duallog <command>` (in PATH). Every clock is LOCAL time.

## Commands

### sessions

#### Input args

`sessions [project] [--since D] [--until D]`

- `project` — substring of the project path or the stem, e.g. `trading`, `ai/trading` or a worker name; omitted lists every session.
- `--since D` / `--until D` — start day, `YYYY-MM-DD`, inclusive.

#### Output

```
START                PROJECT                                      SESSION
2026-09-06 22:27:49  /Users/brunowinter2000/Documents/ai/trading  api_requests_worker_reldist-power_1788726467
2026-09-06 14:47:46  /Users/brunowinter2000/Documents/ai/trading  api_requests_worker_k-ratio_1788698865
2026-09-06 10:10:25  /Users/brunowinter2000/Documents/ai/trading  api_requests_opus_trading_1788682222

3 sessions
```

### reqs

#### Input args

`reqs [scope] [--since D] [--until D] [--main | --worker] [--turn N] [--gap MIN] [--merged] [--rebuild] [--drop]`

- `scope` — substring of the project path or the stem; omitted covers every session.
- `--since D` / `--until D` — start day, `YYYY-MM-DD`, inclusive.
- `--main` / `--worker` — keep only main (opus) or worker sessions.
- `--turn N` — keep only turn N of each session.
- `--gap MIN` — keep only the two REQs around a pause of at least MIN minutes.
- `--merged` — one chronological chain across all sessions in scope, each line tagged with its worker; the cache-health view, since all workers of a project share the prompt cache.
- `--rebuild` — keep only REQs where `CC > CR`, i.e. the prefix was rebuilt.
- `--drop` — keep only REQs that read back less than the previous REQ had cached, i.e. the cache expired in between.
- The flags combine; none adds a column.

#### Output

```
session api_requests_worker_1dda1c81_k-ratio_1788698865
── turn 4  14:57:29  50s  recap ──
REQ 46  14:58:19  CR 149,518  CC 228
── turn 5  18:02:18  8m18s  NEW TASK (same worktree, same area). Read this fully before doing anything. ──
REQ 47  18:02:18  CR 0        CC 152,851
REQ 48  18:02:23  CR 152,851  CC 7,889
```

- A turn runs from one typed prompt (human, or orchestrator via `worker-cli send`) to the model's idle text reply; the separator shows its first send, its span and the prompt.
- `CR` — cache_read_input_tokens, `CC` — cache_creation_input_tokens of that request; `?` when the transcript join failed.
- Under `--merged` the session tag follows the clock on a REQ line and the span on a separator.

### msgs

#### Input args

`msgs <session> [from] [to]` or `msgs <session> --req F [T]`

- `session` — a SESSION value from sessions, or a unique substring of it.
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

- `session` — a SESSION value from sessions, or a unique substring of it.
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
- `scope` — substring of the project path or the stem; omitted searches every session.
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

**The gap between two REQ clocks is model time plus tool time together.**
- The proxy records send times only; where the split lies is not in the logs.

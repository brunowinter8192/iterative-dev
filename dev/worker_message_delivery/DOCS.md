# dev/worker_message_delivery/

## Role

Live probe for text delivery into a worker tmux pane: verifies bracketed paste delivers and submits complete messages on Claude Code 2.1.280 and measures latency. Uses a real claude binary, not a mock.

## Public Interface

No `__init__.py`; run manually: `bash dev/worker_message_delivery/probe_bracketed_paste.sh`.

## Flow

The script generates test messages, boots throwaway claude sessions in scratch git directories, delivers each message through the real send path, verifies delivery from the worker's session JSONL and writes a report to md/.

## Modules

### probe_bracketed_paste.sh (351 LOC)

**Purpose:** Verifies bracketed-paste delivery across four message sizes, contrasts the pre-fix method, and measures paste-to-render latency.
**Reads:** `src/spawn` shell modules (sourced), the claude-280 binary.
**Writes:** stdout; `md/probe_bracketed_paste_report.md`; throwaway sessions and scratch dirs, removed on exit.
**Called by:** Run manually.
**Calls out:** tmux, git, claude-280, python3.

---

### _verify_user_message.py (80 LOC)

**Purpose:** Reads a worker session JSONL, extracts the last user entry, strips the pasted-content wrapper and compares it with the expected message.
**Reads:** JSONL path and expected-message file path (arguments).
**Writes:** stdout key=value lines; exit 0 on exact match, 1 otherwise.
**Called by:** `probe_bracketed_paste.sh` (subprocess).
**Calls out:** Nothing (standard library only).

## State

None.

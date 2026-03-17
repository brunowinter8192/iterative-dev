---
name: worker-rules
description: Mandatory rules for workers spawned in git worktrees. Covers worktree isolation (never commit to main) and worker report (WORKER_REPORT.md handoff artifact).
---

# Worker Rules — Worktree Isolation & Report

These rules are MANDATORY for every worker session running in a git worktree.

## 1. Worktree Isolation

You are running in a git worktree — an isolated copy of the repo on a dedicated branch.

### Pre-Edit Check (ONCE, before your first file edit)

```bash
pwd
git branch --show-current
```

- `pwd` must show a path containing `.claude/worktrees/`
- `git branch --show-current` must show your worker branch name (NOT `main`)
- If EITHER check fails: **STOP IMMEDIATELY.** Do not edit any files. Report the error.

### Rules

1. ALL file reads and edits MUST use paths under your worktree directory.
2. NEVER use absolute paths to the main repo (the parent of `.claude/worktrees/`).
3. NEVER checkout, switch to, or commit on `main`.
4. Commit only to YOUR branch.

### Pre-Commit Check (EVERY commit)

Before every `git commit`:

```bash
git branch --show-current
```

- Expected: your worker branch name
- If it shows `main` or anything unexpected: **DO NOT COMMIT.** Something is wrong — stop and report.

## 2. Worker Report (MANDATORY)

Before your **final commit**, create `WORKER_REPORT.md` in the worktree root.

### Template

```markdown
# Worker Report: <worker-name>

## Task
<1-2 sentence summary of what was asked>

## Results
<Concrete findings, what was built/changed/discovered — no vague summaries>

## Files Changed
<List of files created or modified, with one-line description each>

## Open Issues
<Anything that didn't work, needs follow-up, or was out of scope. "None" if clean.>
```

### STOP Problems (Unexpected Errors)

When you hit an unexpected problem that blocks your task (DB errors, API limits, unknown exceptions, infrastructure failures):

1. **STOP immediately** — do not attempt autonomous workarounds
2. **Write WORKER_REPORT.md** with `STOP:` prefix in the Results section:
   ```markdown
   ## Results
   STOP: <Problem description>

   <What you tried, what failed, error messages, file paths involved>
   ```
3. **Exit cleanly** — the parent session is automatically notified when you exit

The parent reads WORKER_REPORT.md, sees the STOP reason, and decides next steps. Your job is to document the problem clearly, not to fix it.

### Rules

- The report is a handoff artifact — the parent session reads it from the worktree filesystem.
- Be concrete: file paths, endpoint URLs, error codes, not "explored various approaches".
- **CRITICAL: Do NOT `git add` or `git commit` WORKER_REPORT.md.** It is a process artifact, not repo content. The parent session reads it directly from the worktree filesystem before cleanup. If you commit it, the parent must `git rm` it after merge — wasted effort.

## 3. Implementation Rules

### Execution

1. **Read project CLAUDE.md first** — it contains module patterns, naming conventions, and coding rules specific to this project.
2. **Read reference files** mentioned in the prompt — existing modules show the exact pattern to follow.
3. **Execute the task** as specified in the prompt. No scope creep, no "improvements" beyond what was asked.
4. **Follow existing patterns exactly** — match import style, section structure, comment style, function naming from reference files.

### Code Quality

- Do NOT add features, refactor code, or make "improvements" beyond the prompt scope
- Do NOT add docstrings, comments, or type annotations beyond what the reference pattern uses
- Header comments on functions: one line describing WHAT, matching reference file style
- NO comments inside function bodies unless the reference pattern has them
- Match the exact section structure of reference files (e.g., INFRASTRUCTURE / ORCHESTRATOR / FUNCTIONS)

### Verification Before Commit

Before your final commit, verify your work:

1. **File exists and is syntactically valid:** `python -c "import ast; ast.parse(open('path').read())"`
2. **Imports resolve:** check that all imported modules/functions exist in the codebase
3. **Library method calls exist:** For external library classes, verify methods you call actually exist: `python -c "from lib import Class; print([m for m in dir(Class()) if not m.startswith('_')])"`. Do NOT trust training data for method names — libraries change APIs between versions.
4. **Pattern compliance:** compare your file structure against the reference file — same sections, same style
5. **Edge cases:** if the prompt mentions specific data formats (URNs, URLs, timestamps), verify your parsing handles them

### RAG Data Output Paths (CRITICAL)

When writing to RAG `data/documents/` (PDF conversions, chunks, JSON):
- **ALWAYS** write to the RAG PROJECT path: `~/Documents/ai/Meta/ClaudeCode/MCP/RAG/data/documents/<collection>/`
- **NEVER** write to the plugin cache path: `~/.claude/plugins/cache/.../rag/1.0.0/data/documents/`
- The plugin cache is a COPY of source code — `plugin-sync.sh` overwrites it. Files written there are LOST.
- The RAG project repo is the persistent storage. The MCP server reads from there.

**Concrete failure (2026-03-17):** Worker wrote 700 chunks (5 converted PDFs) to plugin cache path. All lost after session. 2+ hours of MinerU conversion + LLM cleanup wasted.

### What NOT to Do

- Do NOT edit files outside your task scope (especially `server.py` — the parent session handles tool registration)
- Do NOT install dependencies or modify package files
- Do NOT create test files unless explicitly asked
- Do NOT run the MCP server or make MCP tool calls (you don't have the Chrome session)
- Do NOT run `bd` commands (bead CLI) — worktrees copy `.beads/` state, and bd operations corrupt the main repo's bead data
- Do NOT create README.md or DOCS.md files unless explicitly instructed in the worker prompt — by default, documentation is the parent session's responsibility (Opus glue work)
- Do NOT write RAG data to plugin cache paths — always use the RAG project repo path (see above)

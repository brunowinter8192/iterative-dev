---
name: rule-consolidation
description: Consolidate new rule observations into existing rule files at end of day. Use when merging accumulated RECAP notes, worker feedback, or session learnings into the permanent rule set under ~/.claude/shared-rules/.
---

# Rule Consolidation

Merge newly accumulated rule observations into the existing rule files.

## Core Principles

### 1. NEVER remove, replace, summarize, or rewrite existing content

Rules are accumulated knowledge. Only the user decides what gets deleted.

- READ the target file fully before editing
- EXTEND existing sections with new content when overlap exists
- ADD new sections when no overlap exists
- MOVE text when restructuring is needed — never delete it
- If unsure whether to remove something → ASK the user

### 2. All rule files are written in English

Every file under `~/.claude/shared-rules/` is English-only. This includes:
- Section headers
- Rule descriptions
- Concrete failure examples
- Tables and lists

German is allowed ONLY in:
- Literal quotes from user conversations ("du sollst X machen")
- Explicit prose examples inside docs where the German phrasing is the point

When consolidating notes written in German (RECAP notes, session observations), translate to English before merging.

## Workflow

To be completed at end of session.

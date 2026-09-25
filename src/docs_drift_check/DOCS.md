# src/docs_drift_check/

## Role

Standalone CLI (`docs-drift-check`), run from a project root, checking every DOCS.md against the DOCS.md rules: referenced paths exist, module-heading LOC equals `wc -l`, no function-level or constant references. Touch when the rules change; there is no whitelist by design.

## Public Interface

`__init__.py` is empty. Entry path: `python3 -m src.docs_drift_check`, run from the plugin root, with the project root passed through an environment variable. `bin/docs-drift-check` does both and is symlinked to `~/.local/bin/docs-drift-check`. Exit 0 = clean, 1 = findings.

## Flow

Project root (environment variable, abort if missing) → collect DOCS.md files and `.py`/`.sh` sources → build symbol index from sources → three checks (paths, LOC, rule violations) → markdown report on stdout, exit code.

## Modules

### __main__.py (26 LOC)

**Purpose:** Orchestrator wiring collection, symbol index, the three checks and the report.
**Reads:** nothing directly.
**Writes:** exit code.
**Called by:** `bin/docs-drift-check` (via `-m src.docs_drift_check`).
**Calls out:** none.

---

### collect.py (30 LOC)

**Purpose:** Walk the project and return DOCS.md files and source files, skipping excluded directories.
**Reads:** project file tree.
**Writes:** nothing.
**Called by:** `__main__.py`.
**Calls out:** none.

---

### symbols.py (50 LOC)

**Purpose:** Build the index of project-defined functions, constants and module owners; recognize module-dot-function references.
**Reads:** source files.
**Writes:** nothing.
**Called by:** `__main__.py`, `check_rules.py`, `check_paths.py`.
**Calls out:** none.

---

### check_paths.py (75 LOC)

**Purpose:** Report backticked paths in DOCS.md files that do not exist.
**Reads:** DOCS.md files, project file tree.
**Writes:** nothing.
**Called by:** `__main__.py`.
**Calls out:** none.

---

### check_loc.py (38 LOC)

**Purpose:** Report module headings whose claimed LOC differs from the actual line count, or whose module file is missing.
**Reads:** DOCS.md files, the module files they name.
**Writes:** nothing.
**Called by:** `__main__.py`.
**Calls out:** none.

---

### check_rules.py (56 LOC)

**Purpose:** Report function-level and constant references to project-defined symbols in DOCS.md files.
**Reads:** DOCS.md files, symbol index.
**Writes:** nothing.
**Called by:** `__main__.py`.
**Calls out:** none.

---

### markdown_scan.py (25 LOC)

**Purpose:** Yield backtick spans per line of a DOCS.md file, outside fenced code blocks.
**Reads:** one DOCS.md file.
**Writes:** nothing.
**Called by:** `check_paths.py`, `check_rules.py`.
**Calls out:** none.

---

### report.py (      27 LOC)

**Purpose:** Print the markdown report and compute the exit code.
**Reads:** findings passed in.
**Writes:** stdout.
**Called by:** `__main__.py`.
**Calls out:** none.

---

### project_root.py (15 LOC)

**Purpose:** Resolve the project root from the environment variable; abort with an error when it is missing.
**Reads:** environment.
**Writes:** stderr and exit code 2 on a missing variable.
**Called by:** `__main__.py`.
**Calls out:** none.

## State

Stateless. Every run recomputes everything from the file tree.

# src/docs_drift_check/

## Role

Standalone CLI (`docs-drift-check`), run from a project root, checking every DOCS.md against the DOCS.md rules of the shared documentation rules. Each report section is named after the rule it checks. Touch when the rules change; there is no whitelist by design.

## Public Interface

`__init__.py` is empty. Entry path: `python3 -m src.docs_drift_check`, run from the plugin root, with the project root passed through an environment variable. `bin/docs-drift-check` does both and is symlinked to `~/.local/bin/docs-drift-check`. It takes no arguments and aborts with exit 2 on any. Exit 0 = clean, 1 = findings.

## Flow

Project root (environment variable, abort if missing) → collect DOCS.md files, `.py`/`.sh` sources and the project path index → build symbol index from sources → one check per rule → markdown report on stdout, one section per rule, exit code.

## Modules

### __main__.py (48 LOC)

**Purpose:** Orchestrator wiring collection, symbol index, the rule checks and the report; owns the rule names used as section titles.
**Reads:** nothing directly.
**Writes:** exit code.
**Called by:** `bin/docs-drift-check` (via `-m src.docs_drift_check`).
**Calls out:** none.

---

### collect.py (60 LOC)

**Purpose:** Walk the project and return DOCS.md files, source files and the path index, skipping excluded and gitignored paths.
**Reads:** project file tree, the git ignore state of the project.
**Writes:** nothing.
**Called by:** `__main__.py`, `check_directories.py`, `check_template.py`.
**Calls out:** none.

---

### symbols.py (55 LOC)

**Purpose:** Build the index of project-defined functions, constants and module owners; environment variable names are not constants.
**Reads:** source files.
**Writes:** nothing.
**Called by:** `__main__.py`, `check_rules.py`.
**Calls out:** none.

---

### markdown_scan.py (61 LOC)

**Purpose:** Read a DOCS.md outside fenced code blocks: lines, backtick spans, sections, module headings and labelled fields.
**Reads:** one DOCS.md file.
**Writes:** nothing.
**Called by:** `check_modules.py`, `check_directories.py`, `check_template.py`, `check_called_by.py`, `check_issues.py`, `check_rules.py`.
**Calls out:** none.

---

### check_modules.py (34 LOC)

**Purpose:** Report module headings that are malformed, name a missing file, or claim a LOC that differs from the actual line count.
**Reads:** DOCS.md files, the module files they name.
**Writes:** nothing.
**Called by:** `__main__.py`.
**Calls out:** none.

---

### check_directories.py (34 LOC)

**Purpose:** Report DOCS.md files without a module of their own directory and module directories without a DOCS.md; an empty `__init__.py` is no module.
**Reads:** DOCS.md files, source files.
**Writes:** nothing.
**Called by:** `__main__.py`.
**Calls out:** none.

---

### check_template.py (55 LOC)

**Purpose:** Report titles that differ from the directory and Role or Purpose texts above the word limits.
**Reads:** DOCS.md files.
**Writes:** nothing.
**Called by:** `__main__.py`.
**Calls out:** none.

---

### check_called_by.py (56 LOC)

**Purpose:** Report empty Called by fields and Called by entries that name no existing file or package, dotted package names included.
**Reads:** DOCS.md files, the project path index.
**Writes:** nothing.
**Called by:** `__main__.py`.
**Calls out:** none.

---

### check_rules.py (52 LOC)

**Purpose:** Report function-level and constant references to project-defined symbols in DOCS.md files.
**Reads:** DOCS.md files, symbol index.
**Writes:** nothing.
**Called by:** `__main__.py`.
**Calls out:** none.

---

### check_issues.py (19 LOC)

**Purpose:** Report DOCS.md lines that point at issues.
**Reads:** DOCS.md files.
**Writes:** nothing.
**Called by:** `__main__.py`.
**Calls out:** none.

---

### report.py (21 LOC)

**Purpose:** Print the markdown report, one section per rule, and compute the exit code.
**Reads:** findings passed in.
**Writes:** stdout.
**Called by:** `__main__.py`.
**Calls out:** none.

---

### project_root.py (32 LOC)

**Purpose:** Resolve the project root from the environment variable, reject command-line arguments and require a git repository; abort with exit 2 otherwise.
**Reads:** environment, command-line arguments, git.
**Writes:** stderr and exit code 2.
**Called by:** `__main__.py`.
**Calls out:** none.

## State

Stateless. Every run recomputes everything from the file tree.

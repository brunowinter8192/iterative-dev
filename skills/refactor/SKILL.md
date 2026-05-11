---
name: refactor
description: Systematic codebase refactor scan. Use when the user asks to scan/audit a project for refactoring opportunities — file-size violations, long functions, argument-mutation anti-patterns, root-module justification, coupling. Runs AST-based audits and produces a prioritized refactor candidate list. NOT for on-the-fly code review (those checks live in worker rules); this is the heavyweight session-level audit.
---

# Refactor Scan

Systematic audit of a codebase against codified standards. Produces concrete refactor candidates ordered by severity. The output of this skill is a prioritized list — implementation of the refactors goes through workers per the standard workflow.

## When to Use

- User asks: "scan for refactor opportunities", "check the codebase", "find what needs cleaning up", "wo könnten wir refactoren"
- Before a major feature addition, to clear technical debt first
- After a long stretch of feature work, to catch accumulated drift

NOT for routine code review — on-the-fly checks live in `~/.claude/shared-rules/worker/code-standards.md` and `code-organization.md` and fire automatically through worker prompts. This skill is the dedicated session-level audit.

## Scope

Python codebases. Source root is the project's `src/` (or equivalent). Filter out runtime artifacts:
- `__pycache__/`
- `logs/` (projects that store live runtime copies there, e.g. Monitor_CC's `.proxy_live_*`)
- `.claude/worktrees/` (in-flight worker copies)
- `venv/`, `.venv/`, `node_modules/`

For non-Python codebases adapt the AST scripts to the equivalent parser; the workflow phases stay the same.

## Workflow

### Phase 1 — Standards Calibration

Confirm which standards apply BEFORE scanning, otherwise documented exceptions get flagged as violations.

1. Read `~/.claude/shared-rules/worker/code-standards.md` and `code-organization.md` — the on-the-fly rules; the skill scans against them.
2. Read the project's `CLAUDE.md` and `src/DOCS.md` — captures project-specific exceptions ("module-level state is documented and intended", "this entry-point lives at root by design").
3. Note documented exceptions explicitly before Phase 2.

### Phase 2 — Five-Dimensional Scan

All five scans run on the same source tree. Each produces evidence; combined output drives Phase 3 prioritization.

#### 2.1 File-LOC against Hard Ceiling

Standard: ≤400 LOC per file (hard), 200-400 = watch-list, 200 with functional groups = split candidate.

```bash
find src -name "*.py" \
  -not -path "*/__pycache__/*" \
  -not -path "*/logs/*" \
  -not -path "*/worktrees/*" \
  | xargs wc -l 2>/dev/null \
  | sort -rn > /tmp/refactor_loc.txt
echo "=== HARD violations (>400) ==="
awk '$1 > 400 && $2 != "total"' /tmp/refactor_loc.txt
echo "=== WATCH (300-400) ==="
awk '$1 > 300 && $1 <= 400 && $2 != "total"' /tmp/refactor_loc.txt
```

#### 2.2 Function-LOC AST Scan

Standard (per code-organization.md): function >50 LOC = extract helper. Above 100 LOC = hard refactor target.

```python
# /tmp/refactor_funclen.py
import ast, os
SKIP = ('__pycache__', '/logs/', '/worktrees/')
results = []
for root, _, files in os.walk('src'):
    if any(x in root for x in SKIP):
        continue
    for fn in files:
        if not fn.endswith('.py'):
            continue
        p = os.path.join(root, fn)
        try:
            tree = ast.parse(open(p).read())
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                loc = (node.end_lineno or 0) - node.lineno
                if loc >= 50:
                    results.append((loc, node.name, p, node.lineno))
results.sort(reverse=True)
print(f"{'LOC':>5}  {'name':<40} {'file':<55} line")
print("-" * 110)
for loc, name, path, line in results:
    print(f"{loc:>5}  {name:<40} {path:<55} {line}")
print(f"\nTotal ≥50 LOC: {len(results)}  |  ≥100: {sum(1 for r in results if r[0]>=100)}")
```

Read with: `python3 /tmp/refactor_funclen.py`

#### 2.3 Argument-Mutation AST Scan

Standard (per code-standards.md Immutability section): functions MUST NOT mutate their arguments. Detects the hidden-side-effect anti-pattern.

```python
# /tmp/refactor_argmut.py
import ast, os
SKIP = ('__pycache__', '/logs/', '/worktrees/')
MUT_METHODS = {'append', 'extend', 'update', 'pop', 'remove',
               'clear', 'insert', 'sort', 'reverse'}
hits = []
for root, _, files in os.walk('src'):
    if any(x in root for x in SKIP):
        continue
    for fn in files:
        if not fn.endswith('.py'):
            continue
        p = os.path.join(root, fn)
        try:
            tree = ast.parse(open(p).read())
        except SyntaxError:
            continue
        for fnode in ast.walk(tree):
            if not isinstance(fnode, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            params = {a.arg for a in fnode.args.args}
            for n in ast.walk(fnode):
                # method call: arg.append(...), arg.update(...), etc.
                if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute):
                    if isinstance(n.func.value, ast.Name) and n.func.value.id in params:
                        if n.func.attr in MUT_METHODS:
                            hits.append((p, n.lineno, fnode.name,
                                         n.func.value.id, n.func.attr))
                # subscript assign: arg[key] = value
                if isinstance(n, ast.Assign):
                    for tgt in n.targets:
                        if isinstance(tgt, ast.Subscript) and isinstance(tgt.value, ast.Name):
                            if tgt.value.id in params:
                                hits.append((p, n.lineno, fnode.name,
                                             tgt.value.id, '__setitem__'))
                # augmented subscript: arg[key] += x
                if isinstance(n, ast.AugAssign):
                    if isinstance(n.target, ast.Subscript) and isinstance(n.target.value, ast.Name):
                        if n.target.value.id in params:
                            hits.append((p, n.lineno, fnode.name,
                                         n.target.value.id, '__iadd__'))
print(f"Total argument-mutation hits: {len(hits)}\n")
clusters = {}
for p, l, fn, arg, op in hits:
    clusters.setdefault((p, fn), []).append((l, arg, op))
for (p, fn), entries in sorted(clusters.items(), key=lambda x: -len(x[1])):
    print(f"  {p} :: {fn}() — {len(entries)} mutation(s)")
    for l, arg, op in entries:
        print(f"      line {l}: {arg}.{op}")
```

Cluster size (mutations per function) reveals the worst offenders — a 12-hit function is a higher refactor priority than 12 single-hit functions.

#### 2.4 Root-Module Multi-Subdir Justification

Standard: standalone modules at `src/` root are only justified if used by ≥2 subdirectories OR they're entry points loaded externally (e.g. mitmproxy `-s`, workflow runner imports).

```bash
echo "=== Root-module import counts ==="
for f in src/*.py; do
  mod=$(basename "$f" .py)
  [ "$mod" = "__init__" ] && continue
  dirs=$(grep -rln "from src.${mod}\|from \.${mod} \|from \.\.${mod}\|import ${mod}$" src \
            --include="*.py" 2>/dev/null \
          | xargs -I{} dirname {} | sort -u | wc -l | tr -d ' ')
  ext=$(grep -l "from src\.${mod}\|import.*\b${mod}\b" *.py 2>/dev/null | head -1)
  echo "  $mod: ${dirs} subdir(s)${ext:+, entry-point: $ext}"
done
```

Decision: ≥2 subdirs OR entry-point reference = JUSTIFIED. Single subdir without entry-point = MOVE candidate.

#### 2.5 Coupling Indicator

Standard (per code-organization.md): >5 cross-module imports = review dependencies, may indicate over-coupling.

```python
# /tmp/refactor_coupling.py
import ast, os
SKIP = ('__pycache__', '/logs/', '/worktrees/')
results = []
for root, _, files in os.walk('src'):
    if any(x in root for x in SKIP):
        continue
    for fn in files:
        if not fn.endswith('.py'):
            continue
        p = os.path.join(root, fn)
        try:
            tree = ast.parse(open(p).read())
        except SyntaxError:
            continue
        modules = set()
        for n in ast.walk(tree):
            if isinstance(n, ast.ImportFrom) and n.module:
                parts = n.module.split('.')
                if parts:
                    modules.add(tuple(parts[:2]))
            elif isinstance(n, ast.Import):
                for a in n.names:
                    modules.add(tuple(a.name.split('.')[:2]))
        if len(modules) > 5:
            results.append((len(modules), p, sorted(modules)))
results.sort(reverse=True)
for count, p, mods in results:
    print(f"{count}  {p}")
    for m in mods:
        print(f"     {'.'.join(m)}")
```

### Phase 3 — Prioritization

Combine the five scan outputs into a single ordered table.

**Severity tiers:**
- **HARD** — file >400 LOC, function ≥100 LOC, argument-mutation cluster ≥4 hits in one function
- **WATCH** — file 300-400 LOC, function 50-99 LOC, single-hit argument mutations
- **STRUCT** — root-module relocations, files with >5 cross-module imports

| Severity | File | Issue | Hits/LOC | Recommendation |
|---|---|---|---|---|
| HARD | path/to/file.py | LOC > 400 | 491 | Split by concern (name them) |
| HARD | path/to/file.py :: func | func ≥100 LOC | 195 | Extract sub-concerns (name them) |
| HARD | path/to/file.py :: func | arg-mutation cluster | 12 hits | Refactor to return new value |
| WATCH | path/to/other.py | LOC 300-400 | 358 | Watch on next change |
| STRUCT | src/foo.py | single-subdir use | — | Move into subdir/ |

### Phase 4 — Refactor Plan

For each HARD item:
- State the concern split — what becomes which module / function
- Identify reference patterns from cleaner files in the same project
- Estimate import-update impact (how many callers need updating)
- Name the worker that will execute the refactor (one worker per coherent unit; do not bundle unrelated refactors)

Implementation goes through workers per `~/.claude/shared-rules/opus/workers-1.md` — Opus does not edit source code.

## Output Format

Findings are presented inline in chat — Opus runs the scans, synthesizes Phase 3 + Phase 4, and reports to the user. No file is written.

The session log already preserves the scan output; writing a separate `dev/refactor_<date>.md` adds a maintenance artifact without operational benefit (workers operate from the inline scope-up, not from a re-read of a saved file).

For ad-hoc invocations (user asks for one specific dimension only), present that dimension's findings; skip the full Phase 3/4 synthesis.

## Anti-Patterns

- Scanning before reading the project's code-standards files → documented exceptions get flagged as violations
- Cosmetic LOC shrinking (trim blanks, merge comments) treated as a split — never counts
- Mixing rule-violations with personal style preferences — this skill audits against codified rules only
- Refactoring without a worker — Opus reviews findings, workers implement
- Bundling unrelated refactors in one worker — corrections required, slower than two focused workers

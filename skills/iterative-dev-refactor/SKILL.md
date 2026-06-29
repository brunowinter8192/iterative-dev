---
name: iterative-dev-refactor
description: Systematic codebase refactor scan. Use when the user asks to scan/audit a project for refactoring opportunities — file-size violations, long functions, argument-mutation anti-patterns, root-module justification, coupling. Runs AST-based audits and produces a prioritized refactor candidate list. NOT for on-the-fly code review (those checks live in worker rules); this is the heavyweight session-level audit.
---

# Refactor Scan

Systematic audit of a codebase against codified standards. Produces concrete refactor candidates ordered by severity. The output of this skill is a prioritized list — implementation of the refactors goes through workers per the standard workflow.

## When to Use

- User asks: "scan for refactor opportunities", "check the codebase", "find what needs cleaning up", "wo könnten wir refactoren"
- Before a major feature addition, to clear technical debt first
- After a long stretch of feature work, to catch accumulated drift

NOT for routine code review — on-the-fly checks live in the worker code-standards and code-organization rules and fire automatically through worker prompts. This skill is the dedicated session-level audit.

## Scope

Python codebases. Source root is the project's `src/` (or equivalent). Filter out runtime artifacts:
- `__pycache__/`
- `logs/` (projects that store live runtime copies there, e.g. Monitor_CC's `.proxy_live_*`)
- `.claude/worktrees/` (in-flight worker copies)
- `venv/`, `.venv/`, `node_modules/`

**Every scan step honors this SKIP scope — including any `subprocess`/`grep` shell-out, not only the AST walks.** Shell-outs must pass `--include='*.py' --exclude-dir=__pycache__ --exclude-dir=logs --exclude-dir=worktrees`, or be replaced by an in-process pass over the already-SKIP-filtered file list (no subprocess at all).

For non-Python codebases adapt the AST scripts to the equivalent parser; the workflow phases stay the same.

## Workflow

### Phase 1 — Standards Calibration

Confirm which standards apply BEFORE scanning.

1. The standards you scan against are the worker code-standards and code-organization rules — already in your context. Calibrate against them.
2. Read the project's `CLAUDE.md` and `src/DOCS.md` — captures project-specific exceptions ("module-level state is documented and intended", "this entry-point lives at root by design").
3. Note documented exceptions explicitly before Phase 2.

### Phase 2 — Multi-Dimensional Scan

Scans run on the same source tree. Each produces evidence; combined output drives Phase 3 prioritization.

Groups:
- **Size** (2.1, 2.2): file and function bloat
- **Immutability** (2.3): argument-mutation anti-pattern
- **Placement** (2.4): root-module justification
- **Cohesion** (2.5, 2.5b, 2.5c): too many concerns at one place — imports, instance attrs, constant clusters
- **Operational Hygiene** (2.6): prototype-to-prod readiness — diagnostic gates, install friction, state-file scattering
- **Refactor Residue** (2.7): accumulated drift — dead imports, scripts in library tree, dev-tooling gaps
- **Control-Flow Integrity** (2.8): silent fallbacks / redundant derivation paths

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

Standard: function >50 LOC = extract helper. Above 100 LOC = hard refactor target.

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

Standard (Immutability): functions MUST NOT mutate their arguments. Detects the hidden-side-effect anti-pattern.

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
            --include="*.py" --exclude-dir=__pycache__ --exclude-dir=logs --exclude-dir=worktrees 2>/dev/null \
          | xargs -I{} dirname {} | sort -u | wc -l | tr -d ' ')
  ext=$(grep -l "from src\.${mod}\|import.*\b${mod}\b" *.py 2>/dev/null | head -1)
  echo "  $mod: ${dirs} subdir(s)${ext:+, entry-point: $ext}"
done
```

Decision: ≥2 subdirs OR entry-point reference = JUSTIFIED. Single subdir without entry-point = MOVE candidate.

#### 2.5 Coupling Indicator

Standard: >5 cross-module imports = review dependencies.

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

#### 2.5b Class State Sprawl

Standard: a class with ≥10 instance attributes = split candidate (conflates concerns). Class-level analog of 2.5 coupling.

```python
# /tmp/refactor_state_sprawl.py
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
        for cls in ast.walk(tree):
            if not isinstance(cls, ast.ClassDef):
                continue
            attrs = set()
            for n in ast.walk(cls):
                if isinstance(n, ast.Assign):
                    for tgt in n.targets:
                        if (isinstance(tgt, ast.Attribute) and
                            isinstance(tgt.value, ast.Name) and tgt.value.id == 'self'):
                            attrs.add(tgt.attr)
                if isinstance(n, ast.AnnAssign):
                    if (isinstance(n.target, ast.Attribute) and
                        isinstance(n.target.value, ast.Name) and n.target.value.id == 'self'):
                        attrs.add(n.target.attr)
            if len(attrs) >= 10:
                results.append((len(attrs), cls.name, p, cls.lineno, sorted(attrs)))
results.sort(reverse=True)
for n_attrs, cname, path, line, attrs in results:
    print(f"{n_attrs:>3}  {cname:<30} {path}:{line}")
    print(f"     attrs: {', '.join(attrs)}")
```

#### 2.5c Constant Concern-Clustering

Standard: module-level UPPER_CASE constants split into ≥2 distinct prefix clusters (each ≥3 constants) = split candidate. Each prefix cluster names a concern that should live in its own module.

```python
# /tmp/refactor_constclust.py
import ast, os, re
from collections import Counter
SKIP = ('__pycache__', '/logs/', '/worktrees/')
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
        prefixes = Counter()
        for n in tree.body:
            if not isinstance(n, ast.Assign):
                continue
            for tgt in n.targets:
                if isinstance(tgt, ast.Name) and tgt.id.isupper():
                    m = re.match(r'^_?([A-Z]+)_', tgt.id)
                    if m:
                        prefixes[m.group(1)] += 1
        clusters = [(pref, n) for pref, n in prefixes.items() if n >= 3]
        if len(clusters) >= 2:
            print(f"{p}: {len(clusters)} prefix clusters")
            for pref, n in sorted(clusters, key=lambda x: -x[1]):
                print(f"     {pref}_*: {n}")
```

#### 2.6 Operational Hygiene

Prototype-to-prod readiness. Three sub-checks.

##### 2.6a Ungated Diagnostic Writes

Standard: file-append calls (`open(path, "a").write(...)`) or stream-redirects to debug/log targets in production code paths MUST be gated by an env-var, debug flag, or log-level check. Common targets: `/tmp/*.log`, `~/*.log`, or any append-mode path with diagnostic naming (`debug`, `trace`, `diag`).

```python
# /tmp/refactor_ungated_diag.py
import ast, os
SKIP = ('__pycache__', '/logs/', '/worktrees/', '/tests/', '/dev/')
DIAG_HINTS = ('/tmp/', '.log', 'debug', 'trace', 'diag')
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
        for n in ast.walk(tree):
            if not (isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
                    and n.func.id == 'open'):
                continue
            if len(n.args) < 2:
                continue
            mode = n.args[1]
            if not (isinstance(mode, ast.Constant) and mode.value in ('a', 'a+', 'w')):
                continue
            path_arg = n.args[0]
            path_str = None
            if isinstance(path_arg, ast.Constant):
                path_str = str(path_arg.value)
            elif isinstance(path_arg, ast.JoinedStr):
                path_str = ''.join(c.value for c in path_arg.values
                                   if isinstance(c, ast.Constant))
            if path_str and any(h in path_str for h in DIAG_HINTS):
                hits.append((p, n.lineno, path_str, mode.value))
for p, ln, ps, m in hits:
    print(f"  {p}:{ln}  open({ps!r}, {m!r})")
# Note: this is a heuristic flag — verify each hit is actually ungated (no env-var
# check up the call tree). AST-based gate detection is imprecise; manual review per hit.
```

##### 2.6b Installation Friction

Standard: configuration files containing placeholder tokens (e.g. `<UPPER_CASE>`-style markers) MUST have an accompanying setup/install script that substitutes them. Applies to plist, yaml, toml, json, conf, and similar config files outside Python code.

```bash
# find non-Python configs with <UPPER> placeholder tokens; flag those without setup_*.py in same dir
for f in $(find . -type f \( -name "*.plist" -o -name "*.yaml" -o -name "*.yml" \
    -o -name "*.toml" -o -name "*.json" -o -name "*.conf" -o -name "*.ini" \) \
    -not -path "*/__pycache__/*" -not -path "*/worktrees/*" \
    -not -path "*/node_modules/*" -not -path "*/venv/*" -not -path "*/.venv/*"); do
  if grep -qE '<[A-Z_]+>' "$f" 2>/dev/null; then
    dir=$(dirname "$f")
    if ! ls "$dir"/setup_*.py "$dir"/install_*.py 2>/dev/null | head -1 > /dev/null; then
      echo "  $f"
      grep -nE '<[A-Z_]+>' "$f" | head -3 | sed 's/^/      /'
    fi
  fi
done
```

##### 2.6c Scattered Application State

Standard: ≥3 application-owned files in `$HOME` with the same project prefix → recommend grouping under XDG-style `~/.config/<project>/` (or platform equivalent).

```bash
# project-aware: pass project_prefix as $1, defaults to cwd basename
PROJECT_PREFIX="${1:-$(basename $(pwd) | tr '[:upper:]' '[:lower:]')}"
count=$(ls -d "$HOME"/.${PROJECT_PREFIX}* 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" -ge 3 ]; then
  echo "  ${count} files in \$HOME match .${PROJECT_PREFIX}*:"
  ls -d "$HOME"/.${PROJECT_PREFIX}* 2>/dev/null | sed 's/^/      /'
  echo "  → recommend grouping under ~/.config/${PROJECT_PREFIX}/"
fi
```

#### 2.7 Refactor Residue

Catch with periodic scans, not on individual change reviews.

##### 2.7a Dead Imports

Standard: imports never referenced in the file.

```bash
# pyflakes-based; install with `pip install pyflakes` if missing
pyflakes src/ 2>&1 | grep "imported but unused" || echo "(none)"
```

##### 2.7b Scripts in Library Tree

Standard: source-tree files containing an `if __name__ == "__main__"` block AND not imported by any other module → they're scripts, not library code. Belong in `scripts/`, `dev/`, or a dedicated `bin/` directory.

```python
# /tmp/refactor_scripts_in_lib.py
# In-process import index — NO subprocess grep (SKIP-filtered walk only).
import ast, os
SKIP = ('__pycache__', '/logs/', '/worktrees/')

# Pass 1 — parse the filtered tree once; collect every module name referenced by an import.
pyfiles = []
imported = set()
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
        pyfiles.append((p, fn, tree))
        for n in ast.walk(tree):
            # from pkg.X import y  /  from . import X  /  from pkg import X
            if isinstance(n, ast.ImportFrom):
                if n.module:
                    imported.add(n.module.split('.')[-1])
                for a in n.names:
                    imported.add(a.name.split('.')[-1])
            # import pkg.X  /  import pkg.X as q
            elif isinstance(n, ast.Import):
                for a in n.names:
                    imported.add(a.name.split('.')[-1])

# Pass 2 — a __main__ file whose module name nobody imports is a script in the lib tree.
candidates = []
for p, fn, tree in pyfiles:
    if fn == '__init__.py':
        continue
    has_main = any(
        isinstance(n, ast.If) and isinstance(n.test, ast.Compare)
        and isinstance(n.test.left, ast.Name) and n.test.left.id == '__name__'
        for n in tree.body
    )
    if not has_main:
        continue
    if os.path.splitext(fn)[0] not in imported:
        candidates.append(p)
for p in candidates:
    print(f"  {p}  (has __main__, not imported elsewhere)")
if not candidates:
    print("  (none)")
```

##### 2.7c Dev-Tooling Gap

Standard: actively-maintained `src/<module>/` directory without any `dev/<module>*` counterpart (script or subdir) = flag. Heuristic — not every module needs a dev counterpart. Active = recent git commits on the module.

```bash
# for each src/<module>/, check dev/<module>* counterpart; flag if module touched <30d ago
for mod in src/*/; do
  mname=$(basename "$mod")
  [ "$mname" = "__pycache__" ] && continue
  if ls dev/${mname}*.py 2>/dev/null > /dev/null || ls -d dev/${mname} 2>/dev/null > /dev/null; then
    continue
  fi
  last_commit=$(git log -1 --format=%ct -- "$mod" 2>/dev/null)
  [ -z "$last_commit" ] && continue
  now=$(date +%s)
  age_days=$(( (now - last_commit) / 86400 ))
  if [ "$age_days" -lt 30 ]; then
    echo "  src/${mname}/ (no dev/${mname}*, last commit ${age_days}d ago)"
  fi
done
```

#### 2.8 Silent-Fallback / Redundant-Derivation Scan

Standard: a code path that, on missing input or failure, produces alternative output through a second method — a fallback — is a refactor target. Distinguish from a **tripwire/assertion** — a check that REFUSES to produce output and surfaces the failure (raise / flag / render-plain-with-marker). The tripwire is the cure, not a violation; the violation is the route that GUESSES an alternative output to keep going.

Per hit, the classifying question: does the flagged branch PRODUCE derived output by a second method (fallback → eliminate), or does it REFUSE and surface (tripwire → keep)? Manual review per hit — a cache-miss returning `None` is a tripwire, not a fallback.

Detection runs three passes.

**Pass 1 — Textual signatures:**
```bash
# markers in comments and names
grep -rniE '\b(fall ?back|legacy path|old path|best.?effort|backward.?compat)\b' src \
  --include='*.py' | grep -vE '/(logs|worktrees|__pycache__)/'
grep -rnE 'def _?\w*(fallback|legacy|dedup|gated)\w*\(' src \
  --include='*.py' | grep -vE '/(logs|worktrees|__pycache__)/'
```

**Pass 2 — Structural signature (AST) — `except` that returns a value without re-raising:**
```python
# /tmp/refactor_silent_except.py
import ast, os
SKIP = ('__pycache__', '/logs/', '/worktrees/', '/dev/', '/tests/')
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
        for n in ast.walk(tree):
            if not isinstance(n, ast.Try):
                continue
            for h in n.handlers:
                produces = any(isinstance(x, ast.Return) and x.value is not None
                               for x in ast.walk(h))
                reraises = any(isinstance(x, ast.Raise) for x in ast.walk(h))
                if produces and not reraises:
                    hits.append((p, h.lineno))
for p, l in hits:
    print(f"  {p}:{l}  except returns a value, no re-raise — silent fallback?")
print(f"\nTotal: {len(hits)} (review each: fallback that guesses vs tripwire that refuses)")
```

**Pass 3 — Cross-module behavioral redundancy (manual — the AST passes do NOT catch this):**

Pass 2 catches single-function silent-excepts. It does NOT catch the same effect achieved via two independent paths across module boundaries — that requires a manual structural read.

For each conceptual value or effect the system produces, map every code site that PRODUCES or READS it. ≥2 independent derivations of the same value/effect = candidate. Patterns:
- Two periodic threads/functions performing the same operation (e.g. two heartbeat loops bumping the same lock).
- One conceptual value read from two different sources that can diverge (e.g. idle computed from two different file mtimes; "is X running" from state-file vs port-scan vs process-scan).
- The same operation implemented in two places with divergent behavior (e.g. one health probe retries, the other does not).
- A hardcoded fallback consulted when the canonical source is absent (e.g. a default port / default path another process can occupy and then masquerade as the real thing).

A sentinel branch feeding two derivations of one output (`if <key> in x: <new path> else: <old path>`) is not reliably AST-detectable; surface it here and during any "are there two ways to compute X" read of the codebase.

**Verify at the source before classifying any Pass-3 candidate:**
- Read the actual code of BOTH paths; confirm they produce/derive the same value/effect.
- For external or library behavior the verdict depends on (does endpoint X block, does the kernel do Y), read the vendored/external source for the categorical answer. Do NOT infer from training knowledge.
- Where cheap, confirm with a live probe (lsof, curl, a one-shot call).

**This dimension does NOT auto-produce a refactor candidate.** Route every hit (all three passes) to the One-Way Redesign Evaluation companion below.

### Phase 3 — Prioritization

Combine the scan outputs into a single ordered table.

**Severity tiers:**
- **HARD** — file >400 LOC, function ≥100 LOC, argument-mutation cluster ≥4 hits in one function, class with ≥15 instance attributes, install-friction (placeholder config) with no setup script
- **WATCH** — file 300-400 LOC, function 50-99 LOC, single-hit argument mutations, class with 10-14 instance attributes, ungated diagnostic writes, scattered application state, scripts in library tree, dead imports
- **STRUCT** — root-module relocations, files with >5 cross-module imports, constant-clustering split candidates, dev-tooling gaps
- **REDESIGN** — silent-fallback / redundant-derivation findings (2.8): NOT a mechanical candidate; route to the One-Way Redesign Evaluation companion for user-collaborative architectural rework

| Severity | File | Issue | Hits/LOC | Recommendation |
|---|---|---|---|---|
| HARD | path/to/file.py | LOC > 400 | 491 | Split by concern (name them) |
| HARD | path/to/file.py :: func | func ≥100 LOC | 195 | Extract sub-concerns (name them) |
| HARD | path/to/file.py :: func | arg-mutation cluster | 12 hits | Refactor to return new value |
| HARD | path/to/file.py :: Cls | class state sprawl | 18 attrs | Split class by concern (name groups) |
| HARD | path/to/config.plist | install friction | N tokens | Add setup_*.py for placeholder substitution |
| WATCH | path/to/other.py | LOC 300-400 | 358 | Watch on next change |
| WATCH | path/to/file.py | ungated diag write | — | Gate by env-var or remove |
| STRUCT | src/foo.py | single-subdir use | — | Move into subdir/ |
| STRUCT | path/to/file.py | constant prefix clusters | 3 clusters | Split file by prefix |
| STRUCT | src/<mod>/ | no dev/ counterpart | — | Add dev/<mod>_debug.py |
| REDESIGN | path/to/file.py | silent fallback / 2nd derivation | — | One-Way Redesign Evaluation (with user) |

### Phase 4 — Refactor Plan

For each HARD item:
- State the concern split — what becomes which module / function
- Identify reference patterns from cleaner files in the same project
- Estimate import-update impact (how many callers need updating)
- Name the worker that will execute the refactor (one worker per coherent unit; do not bundle unrelated refactors)

Implementation goes through workers — Opus does not edit source code.

## Companion Check: Doc Drift (MANDATORY)

Hard rule: a refactor cycle always checks the docs are current before dispatching workers. Run:

```bash
docs-drift-check
```

Universal binary at `~/.local/bin/docs-drift-check`, scans the current project (cwd) for path-existence in indexed docs, LOC-drift in DOCS.md module headings, and symbol-existence in src code (whitelist at `<cwd>/scripts/docs_drift_whitelist.txt` or `<cwd>/.drift-whitelist.txt`). Exit 0 = clean → dispatch. Exit 1 = drift → fix FIRST (separate worker), then dispatch.

Refactor workers update affected DOCS.md alongside the code change — a moved or renamed module updates its DOCS.md in the same commit.

## Companion Check: Symbol-Relocation Reference Audit

When a refactor relocates WHERE a symbol lives — an attribute moved to a different owner object, a function or constant moved to a different module, a name moved into a namespace — EVERY reference to it must be updated to the new access path. This needs its own verification:

**What automated checks miss:** import + entry-point smoke tests validate only the load path. References inside conditionally-executed code (event/callback handlers, error branches, rarely-hit CLI flags, lazy-imported paths) stay stale and fail only at runtime. `docs-drift-check` does not catch it either — a stale `old_path.symbol` access is syntactically valid.

**The audit (worker runs post-implementation, before recap):** for each relocated symbol, grep ALL references and verify each resolves to the new path.

```bash
grep -rnE "\b<old_owner>\b\.?_?<symbol>\b" <affected_tree>
# Expected: references only via the new owner/module; zero via the old path.
```

Whitelist symbols deliberately left in place (e.g. shared state intentionally kept on the original owner — name them so they are not false-flagged). Belongs in the Phase 4 Refactor Plan deliverables for any relocation-type refactor, alongside the doc-drift companion.

## Companion Check: One-Way Redesign Evaluation (Silent-Fallback findings)

A silent-fallback finding (2.8) cannot be auto-fixed by a worker. The fix is a redesign so a SINGLE deterministic route produces the output, correctness guaranteed structurally not guarded at runtime. Evaluated WITH the user. The scan surfaces candidates; this companion is the evaluation process.

**Per candidate, first classify:**
- **Fallback** (eliminate): primary route fails / input missing → produce alternative output by a second method.
- **Tripwire / assertion** (keep, shaped right): check a property; on violation REFUSE to produce output and surface it. Never a second derivation. Leave it (or harden it to refuse-and-surface).

**One-way redesign — work through with the user:**
1. **Record once at the source.** Capture the data at the point of truth (where the operation happens) with enough information — position, identity, order — that a single deterministic path produces the output later, with no re-derivation or inference downstream.
2. **Completeness is a CODE property, not an INPUT property.** Operations happen at a finite, enumerable set of code sites. Completeness is VERIFIED exhaustively across those sites, not hoped for at runtime.
3. **Move the safety check from runtime to test.** Replace the runtime fallback with a test-time invariant: `source + recorded operations == produced output`, asserted over a real corpus and kept as a CI regression test. A failure there = a code site that forgot to record = fix the site.
4. **Production runs one way.** After (1)–(3): one deterministic route, no fallback, no dedup-patch, no "best-effort". Any retained tripwire refuses-and-surfaces; it never guesses.

**Validate in `dev/` before touching `src/`.** Build the redesign as a `dev/` probe, prove exact equivalence on real data across ALL operation types, THEN port to `src/` and delete the fallback chain. Do not modify `src/` during the exploration (dev/-first rule).

**Anti-pattern — the self-defeating hedge:** prove the one-way path in `dev/` and then STILL ship a runtime fallback "just in case". After a passing `dev/` proof with the invariant in CI, production needs no fallback — at most a refuse-and-surface tripwire for genuinely-novel input.

## Companion Check: Skill Prose — What + How, No Why

`skills/*/SKILL.md` files are procedures, not essays. A skill states WHAT it does (capability + output) and HOW to do it (steps, commands, thresholds, output formats, rules — including "do NOT X"). It does NOT explain WHY.

**Removability test (apply per sentence/clause):** can the reader still execute exactly what the skill describes if this clause is removed? If yes → it is WHY → cut it. A concrete example stays only when it shows HOW to decide, not why a choice was made.

**Audit procedure:** for each `SKILL.md` under the repo's `skills/` tree, read it and flag WHY-content by signature:

| Signature | Example | Action |
|---|---|---|
| Justification clause | "raw and maximal — content not captured here is gone for good" | cut the clause, keep the instruction |
| Cause / mechanism explanation | "the plugin cache has NO venv, so a plugin-relative path fails" | cut |
| Rationale section | a section titled "Why X matters" | delete the whole section |
| Historical / evidence note | "(verified on 278 files)", "previous runs failed here" | cut the note |
| Illustrative "what happens otherwise" | "the same anchor on every query just returns the same top sources" | cut |
| `because` / `so that` / `in order to` / `which means` | any clause led by these | cut the clause |

**Keep — never flag as why:** commands, file paths, thresholds, output formats, parameter tables, ordering rules, prohibitions ("do NOT X"), behavior facts the procedure depends on (e.g. "`rag-cli index` is incremental — re-running only embeds new/changed files"), and decision-examples (e.g. "drop off-topic sections — e.g. a REST capture aimed at `search` does not need `enterprise-admin`").

**What to do with findings:** strip the why in place — keep every procedure, command, threshold, and rule intact. `SKILL.md` is documentation-class — Opus edits it directly (no worker). Re-read each edited skill end-to-end to confirm it still reads as an executable procedure.

## Output Format

Findings are presented inline in chat — Opus runs the scans, synthesizes Phase 3 + Phase 4, and reports to the user. No file is written.

For ad-hoc invocations (user asks for one specific dimension only), present that dimension's findings; skip the full Phase 3/4 synthesis.

## Anti-Patterns

- Scanning before calibrating against the code-standards and code-organization rules
- Cosmetic LOC shrinking (trim blanks, merge comments) treated as a split — never counts
- Mixing rule-violations with personal style preferences — this skill audits against codified rules only
- Refactoring without a worker — Opus reviews findings, workers implement
- Bundling unrelated refactors in one worker
- Removing a silent fallback by hand without the one-way redesign + dev/ proof — classify it, evaluate the redesign with the user, prove exact equivalence in dev/, then delete
- Shipping a runtime fallback "just in case" after a passing dev/ proof

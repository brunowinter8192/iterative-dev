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

### Phase 2 — Multi-Dimensional Scan

Scans run on the same source tree. Each produces evidence; combined output drives Phase 3 prioritization.

Groups:
- **Size** (2.1, 2.2): file and function bloat
- **Immutability** (2.3): argument-mutation anti-pattern
- **Placement** (2.4): root-module justification
- **Cohesion** (2.5, 2.5b, 2.5c): too many concerns at one place — imports, instance attrs, constant clusters
- **Operational Hygiene** (2.6): prototype-to-prod readiness — diagnostic gates, install friction, state-file scattering
- **Refactor Residue** (2.7): accumulated drift — dead imports, scripts in library tree, dev-tooling gaps
- **Control-Flow Integrity** (2.8): silent fallbacks / redundant derivation paths — the debugging-hell anti-pattern

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

#### 2.5b Class State Sprawl

Standard: a class with ≥10 instance attributes likely conflates concerns. Symptom: bug-fix in one concern requires reading the entire class because state ownership is unclear. Same dimensional axis as 2.5 coupling (too many things in one place) measured on the class level instead of the import level.

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

Standard: module-level UPPER_CASE constants split into ≥2 distinct prefix clusters (each ≥3 constants) suggest the file conflates concerns. Each prefix cluster names a concern that should live in its own module. Helps surface split candidates even when LOC and import counts are still under the hard ceilings.

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

Prototype-to-prod readiness. Three sub-checks for patterns that work fine in development but bite in production or new-developer onboarding.

##### 2.6a Ungated Diagnostic Writes

Standard: file-append calls (`open(path, "a").write(...)`) or stream-redirects to debug/log targets in production code paths MUST be gated by an env-var, debug flag, or log-level check. Ungated diagnostic writes accumulate unbounded log growth in prod and slow the runtime path. Common targets: `/tmp/*.log`, `~/*.log`, or any append-mode path with diagnostic naming (`debug`, `trace`, `diag`).

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

Standard: configuration files containing placeholder tokens (e.g. `<UPPER_CASE>`-style markers) MUST have an accompanying setup/install script that substitutes them. Without it, manual editing during install creates onboarding friction and version-skew bugs (repo-update overwrites the local substitution). Applies to plist, yaml, toml, json, conf, and similar config files outside Python code.

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

Standard: ≥3 application-owned files in `$HOME` with the same project prefix → recommend grouping under XDG-style `~/.config/<project>/` (or platform equivalent). Reduces user-home clutter, eases backup/uninstall, and signals which files belong to which app.

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

Artifacts from incremental development that accumulate silently. Catch with periodic scans, not on individual change reviews.

##### 2.7a Dead Imports

Standard: imports never referenced in the file. Common after function-extraction, feature-removal, or library-replacement commits. Each dead import is a small noise hit but they compound; also a hint that the relevant refactor wasn't fully completed.

```bash
# pyflakes-based; install with `pip install pyflakes` if missing
pyflakes src/ 2>&1 | grep "imported but unused" || echo "(none)"
```

##### 2.7b Scripts in Library Tree

Standard: source-tree files containing an `if __name__ == "__main__"` block AND not imported by any other module → they're scripts, not library code. Belong in `scripts/`, `dev/`, or a dedicated `bin/` directory. The library tree should be import-only so that the boundary between "loaded as library" and "executed as program" stays clear.

```python
# /tmp/refactor_scripts_in_lib.py
import ast, os, subprocess
SKIP = ('__pycache__', '/logs/', '/worktrees/')
candidates = []
for root, _, files in os.walk('src'):
    if any(x in root for x in SKIP):
        continue
    for fn in files:
        if not fn.endswith('.py') or fn == '__init__.py':
            continue
        p = os.path.join(root, fn)
        try:
            tree = ast.parse(open(p).read())
        except SyntaxError:
            continue
        has_main = False
        for n in tree.body:
            if isinstance(n, ast.If):
                t = n.test
                if (isinstance(t, ast.Compare) and isinstance(t.left, ast.Name)
                        and t.left.id == '__name__'):
                    has_main = True
                    break
        if not has_main:
            continue
        mod_name = os.path.splitext(fn)[0]
        # count grep hits for imports of this module across src/
        r = subprocess.run(['grep', '-rln', '-E',
                            f'(from .*{mod_name}|import.*\\b{mod_name}\\b)', 'src'],
                           capture_output=True, text=True)
        n_imports = len([ln for ln in r.stdout.splitlines() if ln != p])
        if n_imports == 0:
            candidates.append(p)
for p in candidates:
    print(f"  {p}  (has __main__, not imported elsewhere)")
```

##### 2.7c Dev-Tooling Gap

Standard: actively-maintained `src/<module>/` directory without any `dev/<module>*` counterpart (script or subdir) suggests missing debug/probe infrastructure. Heuristic flag — not every module needs a dev counterpart, but actively-iterated UI/runtime modules benefit from a dedicated foreground/probe entry-point for fast iteration. Active = recent git commits on the module.

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

Standard: a code path that, on missing input or failure, SILENTLY produces alternative output through a second method — a fallback — is the highest-severity debugging liability. When two routes can produce the "same" output by different means, a wrong result looks plausible and you cannot tell which route made it. Symptom: you fix one case (whack the mole) and a different case breaks (next mole), because patches (dedup, gating, "best-effort" branches) accrete ON TOP of the fallback instead of removing it. The root data is usually computed once correctly upstream; the fallback re-derives it lossily downstream.

Distinguish from a **tripwire/assertion** — a check that REFUSES to produce output and surfaces the failure (raise / flag / render-plain-with-marker). That is NOT a violation; it is the cure. The violation is specifically the route that GUESSES an alternative output to keep going.

Heuristic — manual review per hit (like 2.6a); some flagged constructs are legitimate (a cache-miss returning `None` is a tripwire, not a fallback). The judgment per hit: does the flagged branch PRODUCE derived output by a second method, or does it REFUSE and surface?

Textual signatures:
```bash
# markers in comments and names
grep -rniE '\b(fall ?back|legacy path|old path|best.?effort|backward.?compat)\b' src \
  --include='*.py' | grep -vE '/(logs|worktrees|__pycache__)/'
grep -rnE 'def _?\w*(fallback|legacy|dedup|gated)\w*\(' src \
  --include='*.py' | grep -vE '/(logs|worktrees|__pycache__)/'
```

Structural signature — `except` that returns a value without re-raising (silent degradation):
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

Structural signature — sentinel branch feeding two derivations of one output (`if <key> in x: <new path>  else: <old path>`): not reliably AST-detectable without per-project knowledge. Surface it during manual review of the textual hits, and during any "why are there two ways to compute X" reading of the codebase.

**This dimension does NOT auto-produce a refactor candidate.** A silent-fallback finding is architectural — its fix is a one-way redesign that MUST be evaluated WITH the user. Route every hit to the One-Way Redesign Evaluation companion below.

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

Implementation goes through workers per `~/.claude/shared-rules/opus/workers-1.md` — Opus does not edit source code.

## Companion Check: Doc Drift (MANDATORY)

This skill audits code structure. Documentation accuracy is a separate axis that MUST also be checked alongside any refactor session — the rules and the tool live in different places, but a real refactor cycle covers both before workers are dispatched.

**Required reading before scoping refactor workers:**

- `~/.claude/shared-rules/global/documentation.md` — documentation hierarchy, IST/Evidenz/SOLL format, Path & Symbol References convention, No-Bead-References rule
- `~/.claude/shared-rules/opus/workers-3.md` § 1.3.3 — Recap-time DOCS Drift Check (script + manual checks)
- `~/.claude/shared-rules/opus/workers-3.md` § 1.3.4 — Recap-time Decisions & Sources Check
- `~/.claude/shared-rules/opus/workers-3.md` § Persistence Routing table — when decisions/ updates vs DOCS.md only vs OldThemes/

**Required action — run the drift check before dispatching refactor workers:**

```bash
docs-drift-check
```

Universal binary at `~/.local/bin/docs-drift-check`, scans the current project (cwd) for: path-existence in indexed docs, LOC-drift in DOCS.md module headings, symbol-existence in src code (whitelist at `<cwd>/scripts/docs_drift_whitelist.txt` or `<cwd>/.drift-whitelist.txt`). Exit code 0 = clean, 1 = drift.

**What to do with findings:**

- Drift IS clean → proceed with refactor worker dispatch.
- Drift found → fix the drift FIRST (worker fix, separate from refactor) so refactor commits land on a clean doc base. Refactor workers updating DOCS.md after the move would otherwise stack on top of existing drift, making both harder to verify post-Recap.

Refactor workers MUST update affected DOCS.md per the file-move checklist (`~/.claude/shared-rules/opus/workers-1.md` § File-Move Checklist) and the Persistence Routing rule (pure refactor → DOCS.md only, no decisions/<step>.md touch unless functional behavior changes per SOLL→IST direction).

The next Recap-time drift check verifies post-refactor state.

## Companion Check: Symbol-Relocation Reference Audit

When a refactor relocates WHERE a symbol lives — an attribute moved to a different owner object, a function or constant moved to a different module, a name moved into a namespace — EVERY reference to it must be updated to the new access path. This needs its own verification because tests miss it:

**Why automated checks miss stale references:** import + entry-point smoke tests validate only the load path. References inside conditionally-executed code (event/callback handlers, error branches, rarely-hit CLI flags, lazy-imported paths) can stay stale, pass every smoke test, and fail only at runtime when that path first executes. `docs-drift-check` does not catch it either — a stale `old_path.symbol` access is syntactically valid and resolves no object-type/attribute analysis.

**The audit (worker runs post-implementation, before recap):** for each relocated symbol, grep ALL references and verify each resolves to the new path.

```bash
grep -rnE "\b<old_owner>\b\.?_?<symbol>\b" <affected_tree>
# Expected: references only via the new owner/module; zero via the old path.
```

Whitelist symbols deliberately left in place (e.g. shared state intentionally kept on the original owner — name them so they are not false-flagged). Belongs in the Phase 4 Refactor Plan deliverables for any relocation-type refactor, alongside the doc-drift companion.

## Companion Check: One-Way Redesign Evaluation (Silent-Fallback findings)

Unlike LOC, mutation, or coupling findings — which a worker refactors mechanically — a silent-fallback finding (2.8) cannot be auto-fixed. Removing a fallback safely requires rebuilding the strategy so a SINGLE deterministic route produces the output, with correctness guaranteed structurally rather than guarded at runtime. That redesign is architectural and is evaluated WITH the user. The scan surfaces candidates; this companion is the evaluation process.

**Per candidate, first classify (the decisive distinction):**
- **Fallback** (eliminate): primary route fails / input missing → produce alternative output by a second method. Hides the failure behind plausible-but-wrong output. This is the debugging hell.
- **Tripwire / assertion** (keep, shaped right): check a property; on violation REFUSE to produce output and surface it. Never a second derivation. Leave it (or harden it to refuse-and-surface).

**One-way redesign — work through with the user:**
1. **Record once at the source.** Can the data be captured at the point of truth (where the operation actually happens) with enough information — position, identity, order — that a single deterministic path produces the output later, with no re-derivation or inference downstream? The downstream re-derivation is almost always the fallback's home.
2. **Completeness is a CODE property, not an INPUT property.** Operations happen at a finite, enumerable set of code sites. New input can only trigger an existing (recorded) site or no operation at all — it cannot manufacture an unrecorded one. So completeness can be VERIFIED exhaustively, not hoped for at runtime.
3. **Move the safety check from runtime to test.** Replace the runtime fallback with a test-time invariant: `source + recorded operations == produced output`, asserted over a real corpus and kept as a CI regression test. A failure there = a code site that forgot to record = fix the site. The test IS the guarantee; it catches future code that forgets to record.
4. **Production runs one way.** After (1)–(3): one deterministic route, no fallback, no dedup-patch, no "best-effort". Any retained tripwire refuses-and-surfaces; it never guesses.

**Validate in `dev/` before touching `src/`.** The redesign is an architectural rewrite — build it as a `dev/` probe, prove exact equivalence on real data across ALL operation types (the invariant holds for every case), THEN port to `src/` and delete the fallback chain. Do not modify `src/` during the exploration (dev/-first rule, `~/.claude/shared-rules/global/documentation.md`).

**Anti-pattern — the self-defeating hedge:** prove the one-way path in `dev/` and then STILL ship a runtime fallback "just in case". That admits you distrust the proof, and it re-introduces the exact hell you set out to remove. If the `dev/` proof holds over the corpus and the invariant lives in CI, production needs no fallback — at most a refuse-and-surface tripwire for genuinely-novel input.

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
- Removing a silent fallback by hand without the one-way redesign + dev/ proof → the fallback's failure mode just relocates; classify it, evaluate the redesign with the user, prove byte/bit-exact equivalence in dev/, then delete
- Shipping a runtime fallback "just in case" after a passing dev/ proof — re-introduces the debugging hell the redesign removed

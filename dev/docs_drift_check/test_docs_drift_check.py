#!/usr/bin/env python3

# INFRASTRUCTURE

import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
WRAPPER = REPO_ROOT / "bin" / "docs-drift-check"

PANES_PY = "def build_cache_turns():\n    return 1\n"
LOC_MODULE = "a = 1\nb = 2\nc = 3\n"

CASES = {
    "clean_project": {
        "files": {
            "src/mod.py": LOC_MODULE,
            "src/DOCS.md": "# src/\n\n### mod.py (3 LOC)\n\n**Purpose:** demo.\n",
        },
        "exit": 0,
        "contains": ["Total:          0"],
        "absent": [],
    },
    "module_function_reference": {
        "files": {
            "src/panes/cache_turns.py": PANES_PY,
            "src/other/DOCS.md": "# other\n\nUses `src/panes/cache_turns.build_cache_turns` for turns.\n",
        },
        "exit": 1,
        "contains": [
            "function-level reference `src/panes/cache_turns.build_cache_turns`",
            "Path-Drift:     0 findings",
        ],
        "absent": ["NOT FOUND"],
    },
    "loc_off_by_one": {
        "files": {
            "dev/proxy/tool.py": LOC_MODULE,
            "dev/proxy/DOCS.md": "# proxy\n\n### tool.py (4 LOC)\n",
        },
        "exit": 1,
        "contains": ["claims `tool.py` = 4 LOC, actual 3 (-1)"],
        "absent": [],
    },
    "loc_heading_without_module_file": {
        "files": {"src/DOCS.md": "# src/\n\n### ghost.py (10 LOC)\n"},
        "exit": 1,
        "contains": ["documents `ghost.py` but the module file does not exist"],
        "absent": [],
    },
    "loc_shell_module": {
        "files": {
            "bin/run.sh": "#!/bin/sh\necho hi\n",
            "bin/DOCS.md": "# bin/\n\n### run.sh (9 LOC)\n",
        },
        "exit": 1,
        "contains": ["claims `run.sh` = 9 LOC, actual 2 (-7)"],
        "absent": [],
    },
    "bash_constant_and_function": {
        "files": {
            "src/spawn.sh": "WORKER_REGISTRY_DIR=/tmp/x\ngo_quiet() {\n  echo q\n}\n",
            "src/DOCS.md": "# src/\n\nReads `WORKER_REGISTRY_DIR` and calls `go_quiet()`.\n",
        },
        "exit": 1,
        "contains": [
            "constant reference `WORKER_REGISTRY_DIR`",
            "function-level reference `go_quiet()`",
        ],
        "absent": [],
    },
    "undefined_symbols_not_flagged": {
        "files": {
            "src/mod.py": "x = 1\n",
            "src/DOCS.md": "# src/\n\nTrap on `EXIT`, git prints `CONFLICT`, uses `os.path`.\n",
        },
        "exit": 0,
        "contains": ["Rule-Violation: 0 findings"],
        "absent": [],
    },
    "python_constant_and_function": {
        "files": {
            "src/mod.py": "MAX_BYTES = 5\n\ndef load():\n    return 1\n",
            "src/DOCS.md": "# src/\n\nCeiling `MAX_BYTES`, entry `load()`.\n",
        },
        "exit": 1,
        "contains": ["constant reference `MAX_BYTES`", "function-level reference `load()`"],
        "absent": [],
    },
    "obsolete_doc_locations_ignored": {
        "files": {
            "decisions/a.md": "See `src/nowhere/missing.py`.\n",
            "sources/sources.md": "See `src/nowhere/missing.py`.\n",
            "src/mod.py": "x = 1\n",
        },
        "exit": 0,
        "contains": ["Total:          0"],
        "absent": ["missing.py"],
    },
    "missing_path_reported": {
        "files": {
            "src/mod.py": "x = 1\n",
            "src/DOCS.md": "# src/\n\nSee `src/gone.py`.\n",
        },
        "exit": 1,
        "contains": ["references `src/gone.py` - NOT FOUND"],
        "absent": [],
    },
    "worktree_docs_excluded": {
        "files": {
            "src/mod.py": "x = 1\n",
            ".claude/worktrees/w/DOCS.md": "### mod.py (99 LOC)\n",
        },
        "exit": 0,
        "contains": ["Total:          0"],
        "absent": [],
    },
    "argparse_metavar_not_constant": {
        "files": {
            "dev/run.sh": "PATH=/usr/bin\n",
            "dev/DOCS.md": "# dev/\n\nRun with `--baseline PATH` or `--out=PATH`.\n",
        },
        "exit": 0,
        "contains": ["Rule-Violation: 0 findings"],
        "absent": [],
    },
    "brace_template_span_skipped": {
        "files": {
            "queries/keep.txt": "x\n",
            "dev/DOCS.md": "# dev/\n\nOutputs in `queries/pass_{a,b,c,d}_runs/`.\n",
        },
        "exit": 0,
        "contains": ["Path-Drift:     0 findings"],
        "absent": ["queries/pass_"],
    },
    "build_artifact_docs_excluded": {
        "files": {
            "src/mod.py": "def run():\n    return 1\n",
            "dist/app/src/DOCS.md": "Calls `run()` and ### mod.py (99 LOC)\n",
        },
        "exit": 0,
        "contains": ["Total:          0"],
        "absent": [],
    },
    "shadowing_project_src_package": {
        "files": {
            "src/__init__.py": "",
            "src/mod.py": LOC_MODULE,
            "src/DOCS.md": "# src/\n\n### mod.py (3 LOC)\n",
        },
        "exit": 0,
        "contains": ["Total:          0"],
        "absent": [],
    },
}

# ORCHESTRATOR

def main() -> int:
    with ThreadPoolExecutor(max_workers=len(CASES) + 1) as pool:
        futures = {name: pool.submit(run_case, name, spec) for name, spec in CASES.items()}
        futures["missing_root_variable_aborts"] = pool.submit(run_without_root_variable)
        results = {name: future.result() for name, future in futures.items()}
    return report(results)

# FUNCTIONS

def run_case(name: str, spec: dict) -> str | None:
    with tempfile.TemporaryDirectory(prefix=f"ddc_{name}_") as tmp:
        project = Path(tmp)
        build_fixture(project, spec["files"])
        completed = run_wrapper(project)
        return verify(completed, spec)

def run_without_root_variable() -> str | None:
    env = {k: v for k, v in os.environ.items() if k != "DOCS_DRIFT_ROOT"}
    completed = subprocess.run(
        [sys.executable, "-m", "src.docs_drift_check"],
        cwd=REPO_ROOT, env=env, capture_output=True, text=True, timeout=60,
    )
    if completed.returncode != 2 or "DOCS_DRIFT_ROOT is not set" not in completed.stderr:
        return f"exit {completed.returncode}\n{completed.stdout}{completed.stderr}"
    return None

def build_fixture(project: Path, files: dict) -> None:
    for rel, content in files.items():
        target = project / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)

def run_wrapper(project: Path) -> subprocess.CompletedProcess:
    env = dict(os.environ, CLAUDE_PLUGIN_ROOT=str(REPO_ROOT))
    return subprocess.run(
        [str(WRAPPER)], cwd=project, env=env, capture_output=True, text=True, timeout=60
    )

def verify(completed: subprocess.CompletedProcess, spec: dict) -> str | None:
    out = completed.stdout
    if completed.returncode != spec["exit"]:
        return f"exit {completed.returncode} != {spec['exit']}\n{out}{completed.stderr}"
    for needle in spec["contains"]:
        if needle not in out:
            return f"missing in output: {needle!r}\n{out}"
    for needle in spec["absent"]:
        if needle in out:
            return f"unexpected in output: {needle!r}\n{out}"
    return None

def report(results: dict) -> int:
    failed = {name: err for name, err in results.items() if err}
    for name in results:
        print(f"{'FAIL' if name in failed else 'PASS'}  {name}")
    for name, err in failed.items():
        print(f"\n--- {name} ---\n{err}")
    print(f"\n{len(results) - len(failed)}/{len(results)} passed")
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())

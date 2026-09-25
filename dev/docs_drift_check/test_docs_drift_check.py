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

T_HEADINGS = "Rule: module heading is '### <file> (<N> LOC)', file in the same directory, LOC equals wc -l"
T_DIRECTORIES = "Rule: one DOCS.md per module directory (.py or .sh files), each naming modules of its own directory"
T_TITLE = "Rule: title is '# <dir>/'"
T_FUNCTIONS = "Rule: no function-level references"
T_CONSTANTS = "Rule: no constant references (environment variables and CLI flags excepted)"
T_WORDS = "Rule: word limits (Role 50, Purpose 25)"
T_CALLED_BY = "Rule: Called by is not empty and names existing files"
T_ISSUES = "Rule: no references to issues"
ALL_TITLES = [T_HEADINGS, T_DIRECTORIES, T_TITLE, T_FUNCTIONS, T_CONSTANTS, T_WORDS, T_CALLED_BY, T_ISSUES]

CLEAN = [f"## {title} (0 findings)" for title in ALL_TITLES]
LOC_MODULE = "a = 1\nb = 2\nc = 3\n"


def doc(directory, module="mod.py", loc=3, role="Demo role.", purpose="Demo.", called="Run manually.", extra="", heading=None):
    heading = heading if heading is not None else f"### {module} ({loc} LOC)"
    text = (
        f"# {directory}/\n\n## Role\n\n{role}\n\n## Modules\n\n{heading}\n\n"
        f"**Purpose:** {purpose}\n**Called by:** {called}\n"
    )
    return text + (f"\n## State\n\n{extra}\n" if extra else "")


def one(title):
    return f"## {title} (1 findings)"


def clean_with(files, **doc_args):
    return {**files, "src/DOCS.md": doc("src", **doc_args)}


CASES = {
    "clean_project": {
        "files": {"src/mod.py": LOC_MODULE, "src/DOCS.md": doc("src")},
        "exit": 0,
        "contains": CLEAN,
        "absent": [],
    },
    "heading_loc_off_by_one": {
        "files": clean_with({"src/mod.py": LOC_MODULE}, loc=4),
        "exit": 1,
        "contains": [one(T_HEADINGS), "claims `mod.py` = 4 LOC, actual 3 (-1)"],
        "absent": [],
    },
    "heading_names_missing_file": {
        "files": {"src/mod.py": LOC_MODULE, "src/DOCS.md": doc("src", module="ghost.py", loc=10)},
        "exit": 1,
        "contains": [one(T_HEADINGS), "documents `ghost.py` but the module file does not exist in this directory"],
        "absent": [],
    },
    "heading_padded_loc_is_malformed": {
        "files": clean_with({"src/mod.py": LOC_MODULE}, heading="### mod.py (      3 LOC)"),
        "exit": 1,
        "contains": [one(T_HEADINGS), "malformed module heading"],
        "absent": [],
    },
    "heading_shell_module": {
        "files": {"bin/run.sh": "#!/bin/sh\necho hi\n", "bin/DOCS.md": doc("bin", module="run.sh", loc=9)},
        "exit": 1,
        "contains": [one(T_HEADINGS), "claims `run.sh` = 9 LOC, actual 2 (-7)"],
        "absent": [],
    },
    "module_directory_without_docs": {
        "files": {"bin/run.sh": "#!/bin/sh\necho hi\n", "src/mod.py": LOC_MODULE, "src/DOCS.md": doc("src")},
        "exit": 1,
        "contains": [one(T_DIRECTORIES), "`bin` holds .py or .sh modules but has no DOCS.md"],
        "absent": [],
    },
    "docs_without_module": {
        "files": {"dev/DOCS.md": "# dev/\n\n## Modules\n\nNone.\n"},
        "exit": 1,
        "contains": [one(T_DIRECTORIES), "`dev/DOCS.md` has no module heading naming a file in its own directory"],
        "absent": [],
    },
    "title_differs_from_directory": {
        "files": {"dev/proxy/tool.py": LOC_MODULE, "dev/proxy/DOCS.md": doc("proxy", module="tool.py")},
        "exit": 1,
        "contains": [one(T_TITLE), "title `# proxy/` should be `# dev/proxy/`"],
        "absent": [],
    },
    "role_above_word_limit": {
        "files": clean_with({"src/mod.py": LOC_MODULE}, role="word " * 51),
        "exit": 1,
        "contains": [one(T_WORDS), "Role has 51 words, maximum 50"],
        "absent": [],
    },
    "purpose_above_word_limit": {
        "files": clean_with({"src/mod.py": LOC_MODULE}, purpose="word " * 26),
        "exit": 1,
        "contains": [one(T_WORDS), "Purpose has 26 words, maximum 25"],
        "absent": [],
    },
    "called_by_empty": {
        "files": clean_with({"src/mod.py": LOC_MODULE}, called=""),
        "exit": 1,
        "contains": [one(T_CALLED_BY), "Called by is empty"],
        "absent": [],
    },
    "called_by_missing_file": {
        "files": clean_with({"src/mod.py": LOC_MODULE}, called="`gone.py`."),
        "exit": 1,
        "contains": [one(T_CALLED_BY), "Called by names `gone.py` which does not exist in the project"],
        "absent": [],
    },
    "called_by_bare_name_resolves": {
        "files": clean_with({"src/mod.py": LOC_MODULE, "tools/runner.txt": "x\n"}, called="`runner.txt` (via `-m pkg.entry`)."),
        "exit": 0,
        "contains": CLEAN,
        "absent": [],
    },
    "issue_reference": {
        "files": clean_with({"src/mod.py": LOC_MODULE}, extra="Tracked in #123."),
        "exit": 1,
        "contains": [one(T_ISSUES), "references an issue (`#123`)"],
        "absent": [],
    },
    "function_reference_module_dot_function": {
        "files": {
            "src/panes/cache_turns.py": "def build_cache_turns():\n    return 1\n",
            "src/panes/DOCS.md": doc("src/panes", module="cache_turns.py", loc=2, extra="Uses `src/panes/cache_turns.build_cache_turns`."),
        },
        "exit": 1,
        "contains": [one(T_FUNCTIONS), "function-level reference `src/panes/cache_turns.build_cache_turns`"],
        "absent": ["NOT FOUND"],
    },
    "bash_constant_and_function": {
        "files": {
            "src/spawn.sh": "WORKER_REGISTRY_DIR=/tmp/x\ngo_quiet() {\n  echo q\n}\n",
            "src/DOCS.md": doc("src", module="spawn.sh", loc=4, extra="Reads `WORKER_REGISTRY_DIR` and calls `go_quiet()`."),
        },
        "exit": 1,
        "contains": [one(T_CONSTANTS), one(T_FUNCTIONS), "constant reference `WORKER_REGISTRY_DIR`", "function-level reference `go_quiet()`"],
        "absent": [],
    },
    "python_constant_and_function": {
        "files": {
            "src/mod.py": "MAX_BYTES = 5\n\ndef load():\n    return 1\n",
            "src/DOCS.md": doc("src", loc=4, extra="Ceiling `MAX_BYTES`, entry `load()`."),
        },
        "exit": 1,
        "contains": [one(T_CONSTANTS), one(T_FUNCTIONS), "constant reference `MAX_BYTES`", "function-level reference `load()`"],
        "absent": [],
    },
    "undefined_symbols_not_flagged": {
        "files": clean_with({"src/mod.py": LOC_MODULE}, extra="Trap on `EXIT`, git prints `CONFLICT`, uses `os.path`."),
        "exit": 0,
        "contains": CLEAN,
        "absent": [],
    },
    "environment_variables_not_constants": {
        "files": {
            "src/mod.py": 'import os\nMONITOR_CC_ROOT = "x"\nroot = os.environ.get("MONITOR_CC_ROOT")\n',
            "src/DOCS.md": doc("src", extra="Reads `MONITOR_CC_ROOT` from the environment."),
            "bin/run.sh": 'WORKER_LOGGER_DIR="${WORKER_LOGGER_DIR:-/tmp}"\n',
            "bin/DOCS.md": doc("bin", module="run.sh", loc=1, extra="Reads `WORKER_LOGGER_DIR` from the environment."),
        },
        "exit": 0,
        "contains": CLEAN,
        "absent": [],
    },
    "argparse_metavar_not_constant": {
        "files": {
            "dev/run.sh": "PATH=/usr/bin\n",
            "dev/DOCS.md": doc("dev", module="run.sh", loc=1, extra="Run with `--baseline PATH` or `--out=PATH`."),
        },
        "exit": 0,
        "contains": CLEAN,
        "absent": [],
    },
    "obsolete_doc_locations_ignored": {
        "files": clean_with({
            "decisions/a.md": "See #123 and `src/nowhere/missing.py`.\n",
            "sources/sources.md": "See `src/nowhere/missing.py`.\n",
            "src/mod.py": LOC_MODULE,
        }),
        "exit": 0,
        "contains": CLEAN,
        "absent": ["missing.py"],
    },
    "worktree_docs_excluded": {
        "files": clean_with({"src/mod.py": LOC_MODULE, ".claude/worktrees/w/DOCS.md": "### mod.py (99 LOC)\n"}),
        "exit": 0,
        "contains": CLEAN,
        "absent": [],
    },
    "build_artifact_docs_excluded": {
        "files": clean_with({"src/mod.py": LOC_MODULE, "dist/app/src/DOCS.md": "Calls `run()` and ### mod.py (99 LOC)\n"}),
        "exit": 0,
        "contains": CLEAN,
        "absent": [],
    },
    "shadowing_project_src_package": {
        "files": clean_with({"src/__init__.py": "", "src/mod.py": LOC_MODULE}),
        "exit": 0,
        "contains": CLEAN,
        "absent": [],
    },
    "unknown_argument_rejected": {
        "files": {"src/mod.py": LOC_MODULE, "src/DOCS.md": doc("src")},
        "args": ["src"],
        "exit": 2,
        "contains": ["takes no arguments", "got: src"],
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
        completed = run_wrapper(project, spec.get("args", []))
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

def run_wrapper(project: Path, args: list) -> subprocess.CompletedProcess:
    env = dict(os.environ, CLAUDE_PLUGIN_ROOT=str(REPO_ROOT))
    return subprocess.run(
        [str(WRAPPER), *args], cwd=project, env=env, capture_output=True, text=True, timeout=60
    )

def verify(completed: subprocess.CompletedProcess, spec: dict) -> str | None:
    out = completed.stdout + completed.stderr
    if completed.returncode != spec["exit"]:
        return f"exit {completed.returncode} != {spec['exit']}\n{out}{completed.stderr}"
    for needle in spec["contains"]:
        if needle not in out:
            return f"missing in output: {needle!r}\n{out}"
    if "## Summary" in out:
        return f"unexpected Summary section\n{out}"
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

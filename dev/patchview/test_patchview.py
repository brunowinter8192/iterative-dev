#!/usr/bin/env python3

# INFRASTRUCTURE

import contextlib
import hashlib
import html
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

_HERE = Path(__file__).parent.resolve()
sys.path.insert(0, str(_HERE.parents[1]))

from dev.strand_runner import run_strands
from src.patchview.__main__ import patchview_workflow

ROW_PATTERN = re.compile(r'<div class="(eq|del|add)"><span class="s">.</span>(.*?)</div>')
LIVE_TEXT = "\n".join(
    ["# Rules", "", "alpha", "beta <b> & gamma", "delta", "", "## Part two", "one", "two", "three", "four", "five", "six", "seven"]
) + "\n"
NEW_TEXT = "\n".join(
    ["# Rules", "", "alpha", "beta CHANGED", "delta", "", "## Part two", "one", "two", "three", "four", "five", "inserted", "six"]
) + "\n"

# ORCHESTRATOR

def test_patchview_workflow() -> int:
    cases = {
        "applies": test_patch_renders_whole_file_with_red_green,
        "offset": test_shifted_hunks_still_apply,
        "stale": test_stale_patch_fails_and_touches_nothing,
        "bad_argv": test_bad_argv_exits_2,
        "missing_live": test_missing_live_file_exits_1,
        "foreign_src": test_wrapper_works_from_cwd_with_own_src_package,
    }
    code, _ = run_strands(cases, sys.argv[1:])
    return code

# FUNCTIONS

def check(name: str, condition: bool, detail: str = "") -> None:
    if not condition:
        raise AssertionError(f"{name}  {detail}")
    print(f"  PASS: {name}")


@contextlib.contextmanager
def sandbox():
    with tempfile.TemporaryDirectory() as root:
        saved = os.environ.get("TMPDIR")
        os.environ["TMPDIR"] = os.path.join(root, "tmp")
        os.makedirs(os.environ["TMPDIR"])
        try:
            yield Path(root)
        finally:
            if saved is None:
                del os.environ["TMPDIR"]
            else:
                os.environ["TMPDIR"] = saved


def make_patch(root: Path, live: Path, new_text: str) -> Path:
    new = root / "new.md"
    new.write_text(new_text)
    out = subprocess.run(["diff", "-u", str(live), str(new)], capture_output=True, text=True).stdout
    patch = root / "proposal.patch"
    patch.write_text(out)
    return patch


def run(argv):
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        code = patchview_workflow(argv)
    return code, out.getvalue(), err.getvalue()


def rows_of(page_path: str) -> list:
    rows = ROW_PATTERN.findall(Path(page_path).read_text())
    return [(kind, "" if text == "&nbsp;" else html.unescape(text)) for kind, text in rows]


def digest_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_patch_renders_whole_file_with_red_green():
    with sandbox() as root:
        live = root / "live.md"
        live.write_text(LIVE_TEXT)
        patch = make_patch(root, live, NEW_TEXT)
        before = digest_of(live)
        code, out, err = run([str(patch)])
        check("exit code 0", code == 0, (code, err))
        check("stderr empty", err == "", err)
        page_path = out.strip()
        check("page lives under TMPDIR/patchview", page_path.startswith(os.path.join(os.environ["TMPDIR"], "patchview") + os.sep), page_path)
        expected = [
            ("eq", "# Rules"), ("eq", ""), ("eq", "alpha"),
            ("del", "beta <b> & gamma"), ("add", "beta CHANGED"),
            ("eq", "delta"), ("eq", ""), ("eq", "## Part two"), ("eq", "one"), ("eq", "two"),
            ("eq", "three"), ("eq", "four"), ("eq", "five"),
            ("add", "inserted"), ("eq", "six"), ("del", "seven"),
        ]
        check("rows are the whole file with exact red/green marking", rows_of(page_path) == expected, rows_of(page_path))
        check("escaped markup in the page source", "beta &lt;b&gt; &amp; gamma" in Path(page_path).read_text())
        check("live file untouched", digest_of(live) == before)


def test_shifted_hunks_still_apply():
    with sandbox() as root:
        live = root / "live.md"
        live.write_text(LIVE_TEXT)
        patch = make_patch(root, live, NEW_TEXT)
        shifted = "user line 1\nuser line 2\nuser line 3\n" + LIVE_TEXT.replace("two\n", "two\nuser edit in the gap\n", 1)
        live.write_text(shifted)
        before = digest_of(live)
        code, out, err = run([str(patch)])
        check("exit code 0 despite shifted line numbers", code == 0, (code, err))
        rows = rows_of(out.strip())
        check("user lines are shown plain", rows[:3] == [("eq", "user line 1"), ("eq", "user line 2"), ("eq", "user line 3")], rows[:3])
        check("user edit between hunks is shown plain", ("eq", "user edit in the gap") in rows, rows)
        check("first hunk marks the right lines", ("del", "beta <b> & gamma") in rows and ("add", "beta CHANGED") in rows, rows)
        check("second hunk marks the right lines", ("add", "inserted") in rows and ("del", "seven") in rows, rows)
        old_side = [t for k, t in rows if k != "add"]
        check("old side of the page equals the live file", old_side == shifted.split("\n")[:-1], old_side)
        check("live file untouched", digest_of(live) == before)


def test_stale_patch_fails_and_touches_nothing():
    with sandbox() as root:
        live = root / "live.md"
        live.write_text(LIVE_TEXT)
        patch = make_patch(root, live, NEW_TEXT)
        live.write_text(LIVE_TEXT.replace("beta <b> & gamma", "beta edited by the user"))
        before = digest_of(live)
        code, out, err = run([str(patch)])
        check("exit code 1", code == 1, code)
        check("stdout empty", out == "", out)
        check("stderr says stale and names the hunk", "STALE PATCH" in err and "hunk 1" in err, err)
        check("no page written", not (Path(os.environ["TMPDIR"]) / "patchview").exists() or not any((Path(os.environ["TMPDIR"]) / "patchview").iterdir()))
        check("live file untouched", digest_of(live) == before)


def test_bad_argv_exits_2():
    code0, out0, err0 = run([])
    code2, out2, err2 = run(["a", "b"])
    check("no args exits 2 with usage", code0 == 2 and out0 == "" and "usage" in err0, (code0, out0, err0))
    check("two args exits 2 with usage", code2 == 2 and out2 == "" and "usage" in err2, (code2, out2, err2))


def test_missing_live_file_exits_1():
    with sandbox() as root:
        live = root / "live.md"
        live.write_text(LIVE_TEXT)
        patch = make_patch(root, live, NEW_TEXT)
        live.unlink()
        code, out, err = run([str(patch)])
        check("exit code 1", code == 1, code)
        check("stdout empty", out == "", out)
        check("stderr names the live file", str(live) in err, err)


def test_wrapper_works_from_cwd_with_own_src_package():
    with sandbox() as root:
        repo_bin = root / "repo" / "bin"
        repo_bin.mkdir(parents=True)
        shutil.copy2(_HERE.parents[1] / "bin" / "patchview", repo_bin / "patchview")
        (repo_bin / "show").write_text('#!/usr/bin/env bash\necho "$1" > "$(dirname "$0")/shown.txt"\n')
        (repo_bin / "show").chmod(0o755)
        (root / "repo" / "src").symlink_to(_HERE.parents[1] / "src")
        work = root / "work"
        (work / "src").mkdir(parents=True)
        (work / "src" / "__init__.py").write_text("")
        (work / "dev" / "area" / "patch").mkdir(parents=True)
        live = root / "live.md"
        live.write_text(LIVE_TEXT)
        make_patch(root, live, NEW_TEXT).rename(work / "dev" / "area" / "patch" / "p.patch")
        before = digest_of(live)
        result = subprocess.run(
            [str(repo_bin / "patchview"), "dev/area/patch/p.patch"],
            cwd=work, capture_output=True, text=True, env={**os.environ, "TMPDIR": os.environ["TMPDIR"]},
        )
        check("exit code 0 from a cwd with its own src package", result.returncode == 0, (result.returncode, result.stderr))
        shown = (repo_bin / "shown.txt").read_text().strip()
        check("show received the page path", shown.startswith(os.path.join(os.environ["TMPDIR"], "patchview")) and shown.endswith(".html"), shown)
        check("page holds the patched file", ("add", "beta CHANGED") in rows_of(shown), rows_of(shown))
        check("live file untouched", digest_of(live) == before)


if __name__ == "__main__":
    sys.exit(test_patchview_workflow())

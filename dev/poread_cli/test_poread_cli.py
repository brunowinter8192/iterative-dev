#!/usr/bin/env python3

# INFRASTRUCTURE

import hashlib
import io
import os
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

_HERE = Path(__file__).parent.resolve()
sys.path.insert(0, str(_HERE.parents[1]))

from dev.strand_runner import run_strands
from src.poread_cli.__main__ import main

_PINNED_MAX_BYTES = 50_000
_PINNED_HASH_LEN = 16
_PINNED_MARKER_PREFIX = '<poread-export '
_PINNED_NOTICE = (
    "The file's full content will arrive automatically on the next turn — do not read "
    "this file again until then."
)

# FUNCTIONS

def check(name: str, condition: bool, detail: str = "") -> None:
    if not condition:
        raise AssertionError(f"{name}  {detail}")
    print(f"  PASS: {name}")


def _run(argv):
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        code = main(argv)
    return code, out.getvalue(), err.getvalue()


def test_valid_file_prints_marker():
    with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as f:
        data = b"line one\nline two\n"
        f.write(data)
        path = f.name
    try:
        code, out, err = _run([path])
        expected_hash = hashlib.sha256(data).hexdigest()[:_PINNED_HASH_LEN]
        abs_path = os.path.realpath(path)
        expected = f'{_PINNED_MARKER_PREFIX}path="{abs_path}" bytes="{len(data)}" sha256="{expected_hash}"/>\n{_PINNED_NOTICE}\n'
        check("exit code 0 for a valid file", code == 0, code)
        check("stdout is exactly the marker line plus the notice line, nothing else", out == expected, repr(out))
        check("stderr is empty on success", err == "", repr(err))
    finally:
        os.unlink(path)


def test_oversize_file_refused_without_reading():
    with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as f:
        f.seek(_PINNED_MAX_BYTES)
        f.write(b'\0')
        path = f.name
    try:
        import src.poread_cli.__main__ as mod

        def _fail_if_opened(*a, **kw):
            raise AssertionError("poread must not open() an oversize file at all")
        mod.open = _fail_if_opened
        try:
            code, out, err = _run([path])
        finally:
            del mod.open
        check("exit code 1 for an oversize file", code == 1, code)
        check("no marker printed for an oversize file", out == "", repr(out))
        check("stderr names the ceiling and refuses", "over the" in err and str(_PINNED_MAX_BYTES) in err, repr(err))
        check("stderr says no truncated/partial export", "truncated" in err or "partial" in err, repr(err))
    finally:
        os.unlink(path)


def test_missing_file_refused():
    missing = os.path.join(tempfile.mkdtemp(), "definitely_missing.txt")
    code, out, err = _run([missing])
    check("exit code 1 for a missing file", code == 1, code)
    check("no marker printed for a missing file", out == "", repr(out))
    check("stderr mentions the path", missing in err or os.path.realpath(missing) in err, repr(err))


def test_directory_refused_not_treated_as_file():
    with tempfile.TemporaryDirectory() as d:
        code, out, err = _run([d])
        check("exit code 1 for a directory path", code == 1, code)
        check("no marker printed for a directory path", out == "", repr(out))
        check("stderr says not a file", "not a file" in err, repr(err))


def test_bad_argv_exits_2():
    code0, out0, err0 = _run([])
    code2, out2, err2 = _run(["a", "b"])
    check("no-args exits 2", code0 == 2, code0)
    check("no-args prints usage, no marker", out0 == "" and "usage" in err0, (out0, err0))
    check("two-args exits 2", code2 == 2, code2)
    check("two-args prints usage, no marker", out2 == "" and "usage" in err2, (out2, err2))


# ORCHESTRATOR

def test_poread_cli_workflow() -> int:
    cases = {
        "valid_file": test_valid_file_prints_marker,
        "oversize_file": test_oversize_file_refused_without_reading,
        "missing_file": test_missing_file_refused,
        "directory": test_directory_refused_not_treated_as_file,
        "bad_argv": test_bad_argv_exits_2,
    }
    code, _ = run_strands(cases, sys.argv[1:])
    return code


if __name__ == "__main__":
    sys.exit(test_poread_cli_workflow())

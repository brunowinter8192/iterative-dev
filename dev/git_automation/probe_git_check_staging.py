# INFRASTRUCTURE

import datetime
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
REPORT_DIR = Path(__file__).resolve().parent / "md"


# ORCHESTRATOR

def run_probe() -> None:
    cases = [
        case_git_check_auto_stage,
    ]
    results = []
    for case in cases:
        ok, name, detail = case()
        results.append((ok, name, detail))
        print(f"[{'PASS' if ok else 'FAIL'}] {name}")
        print(f"    {detail}")

    write_report(results)
    if any(not ok for ok, _, _ in results):
        print("\nprobe FAILED — see report for details")
        sys.exit(1)
    print("\nprobe PASSED — all cases green")


# FUNCTIONS

def sh(cmd: list, cwd=None, check: bool = False):
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(f"setup command failed: {cmd} -> {result.stderr}")
    return result.returncode, result.stdout, result.stderr


def make_repo() -> Path:
    repo = Path(tempfile.mkdtemp(prefix="git_check_probe_"))
    sh(["git", "init", "-q"], cwd=repo, check=True)
    sh(["git", "config", "user.email", "brunowinter8192@github.com"], cwd=repo, check=True)
    sh(["git", "config", "user.name", "Bruno Winter"], cwd=repo, check=True)
    (repo / "README.md").write_text("probe repo\n")
    sh(["git", "add", "README.md"], cwd=repo, check=True)
    sh(["git", "commit", "-q", "-m", "initial"], cwd=repo, check=True)
    return repo


def run_git_check(repo: Path):
    return sh(["python3", "-m", "src.git.check", str(repo), "--auto-stage"], cwd=PROJECT_ROOT)


def _force_writable(func, path, exc_info):
    os.chmod(path, 0o755)
    func(path)


def cleanup(repo: Path):
    shutil.rmtree(repo, onerror=_force_writable)


def case_git_check_auto_stage():
    name = "git-check --auto-stage stages umlaut and space paths"
    repo = make_repo()
    try:
        folder = repo / "anhänge"
        folder.mkdir()
        (folder / "schäden.pdf").write_bytes(b"binary\n")
        (repo / "spaced file.txt").write_text("x\n")

        rc, out, err = run_git_check(repo)
        _, cached, _ = sh(["git", "diff", "--cached", "--name-only", "-z"], cwd=repo)
        cached_files = [p for p in cached.split("\0") if p]
        ok = (
            rc == 0
            and "anhänge/schäden.pdf" in cached_files
            and "spaced file.txt" in cached_files
            and "STAGE ERRORS" not in out
        )
        return ok, name, f"rc={rc} cached={cached_files}"
    finally:
        cleanup(repo)


def write_report(results: list[tuple[bool, str, str]]):
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    path = REPORT_DIR / f"probe_git_check_staging_{ts}.md"
    lines = [
        "# git-check non-ASCII staging probe",
        "",
        f"Run: {ts}",
        "",
        "| Result | Case |",
        "|---|---|",
    ]
    for ok, case_name, _ in results:
        lines.append(f"| {'PASS' if ok else 'FAIL'} | {case_name} |")
    lines.append("")
    lines.append("## Details")
    for ok, case_name, detail in results:
        lines.append(f"\n### {case_name} — {'PASS' if ok else 'FAIL'}\n\n{detail}")
    path.write_text("\n".join(lines) + "\n")
    print(f"\nreport written: {path}")


if __name__ == "__main__":
    run_probe()

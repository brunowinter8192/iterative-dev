# INFRASTRUCTURE
import os
import subprocess
from typing import Literal

from fastmcp import FastMCP
from mcp.types import TextContent

mcp = FastMCP("iterative-dev")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TMUX_SPAWN_SH = os.path.join(SCRIPT_DIR, "src", "spawn", "tmux_spawn.sh")


# HELPERS

def _run_bd(args: list[str], repo: str | None = None) -> str:
    """Run bd CLI and return stdout."""
    cmd = ["bd"]
    if repo:
        cmd += ["--db", os.path.join(repo, ".beads", "dolt")]
    cmd += args
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        return f"ERROR: {result.stderr.strip()}"
    return result.stdout.strip()


def _run_bd_create(args: list[str], repo: str | None = None) -> str:
    """Run bd create with --repo flag (different from --db for other commands)."""
    cmd = ["bd"]
    if repo:
        cmd += ["--repo", repo]
    cmd += args
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        return f"ERROR: {result.stderr.strip()}"
    return result.stdout.strip()


def _run_tmux(func_call: str) -> str:
    """Source tmux_spawn.sh and run a function."""
    cmd = f'source "{TMUX_SPAWN_SH}" && {func_call}'
    result = subprocess.run(
        ["bash", "-c", cmd],
        capture_output=True, text=True, timeout=60,
        cwd=os.getcwd()
    )
    if result.returncode != 0:
        return f"ERROR: {result.stderr.strip()}"
    return result.stdout.strip()


def _run_git(args: list[str], cwd: str | None = None) -> str:
    """Run git command and return stdout."""
    result = subprocess.run(
        ["git"] + args,
        capture_output=True, text=True, timeout=30,
        cwd=cwd or os.getcwd()
    )
    if result.returncode != 0:
        return f"ERROR: {result.stderr.strip()}"
    return result.stdout.strip()


# TOOLS — Beads

@mcp.tool
def bead_list(
    status: Literal["open", "closed"] = "open",
    repo: str | None = None
) -> list[TextContent]:
    """List beads by status."""
    output = _run_bd(["list", "-s", status], repo)
    return [TextContent(type="text", text=output)]


@mcp.tool
def bead_show(
    id: str,
    repo: str | None = None
) -> list[TextContent]:
    """Show bead description and comments."""
    desc = _run_bd(["show", id], repo)
    comments = _run_bd(["comments", id], repo)
    output = f"{desc}\n\n--- COMMENTS ---\n\n{comments}"
    return [TextContent(type="text", text=output)]


@mcp.tool
def bead_create(
    title: str,
    description: str,
    type: Literal["task"] = "task",
    labels: str | None = None,
    repo: str | None = None
) -> list[TextContent]:
    """Create a new bead."""
    args = ["create", "--title", title, "--type", type, "--description", description]
    if labels:
        args += ["--labels", labels]
    output = _run_bd_create(args, repo)
    return [TextContent(type="text", text=output)]


@mcp.tool
def bead_comment(
    id: str,
    text: str,
    repo: str | None = None
) -> list[TextContent]:
    """Add comment to a bead."""
    output = _run_bd(["comments", "add", id, text], repo)
    return [TextContent(type="text", text=output)]


@mcp.tool
def bead_close(
    id: str,
    reason: str
) -> list[TextContent]:
    """Close a bead with reason."""
    output = _run_bd(["close", id, f"--reason={reason}"])
    return [TextContent(type="text", text=output)]


# TOOLS — Workers

@mcp.tool
def worker_list(
    project_path: str | None = None
) -> list[TextContent]:
    """List active workers for project."""
    path = project_path or os.getcwd()
    output = _run_tmux(f'worker_list "{path}"')
    return [TextContent(type="text", text=output or "No active workers.")]


@mcp.tool
def worker_status(
    name: str,
    project_path: str | None = None
) -> list[TextContent]:
    """Check single worker status."""
    path = project_path or os.getcwd()
    output = _run_tmux(f'worker_status "{name}" "{path}"')
    return [TextContent(type="text", text=output)]


@mcp.tool
def worker_capture(
    name: str,
    lines: int | None = None,
    tail: int | None = None,
    project_path: str | None = None
) -> list[TextContent]:
    """Capture worker pane output to file. Use tail to get last N lines directly."""
    path = project_path or os.getcwd()
    if lines:
        output = _run_tmux(f'worker_capture "{name}" {lines} "{path}"')
    else:
        output = _run_tmux(f'worker_capture "{name}" "" "{path}"')
    if tail and output and not output.startswith("ERROR"):
        filepath = output.strip()
        try:
            with open(filepath, "r") as f:
                all_lines = f.readlines()
            tail_content = "".join(all_lines[-tail:])
            return [TextContent(type="text", text=tail_content)]
        except Exception:
            pass
    return [TextContent(type="text", text=output)]


@mcp.tool
def worker_send(
    name: str,
    message: str,
    project_path: str | None = None
) -> list[TextContent]:
    """Send message to running worker."""
    path = project_path or os.getcwd()
    safe_msg = message.replace('"', '\\"')
    output = _run_tmux(f'worker_send "{name}" "{safe_msg}" "{path}"')
    return [TextContent(type="text", text=output or "Message sent.")]


@mcp.tool
def worker_spawn(
    name: str,
    prompt_file: str,
    project_path: str,
    model: Literal["sonnet", "opus"] = "sonnet",
    worktree: bool = True
) -> list[TextContent]:
    """Spawn worker with optional worktree isolation."""
    results = []

    if not os.path.isfile(prompt_file):
        return [TextContent(type="text", text=f"ERROR: Prompt file not found: {prompt_file}")]

    actual_path = project_path

    if worktree:
        # Pre-flight: check gitignored files
        wt_path = os.path.join(project_path, ".claude", "worktrees", name)

        # Create worktree
        branch_check = _run_git(["branch", "--list", name], cwd=project_path)
        if branch_check.strip():
            return [TextContent(type="text", text=f"ERROR: Branch '{name}' already exists. Clean up first.")]

        wt_result = _run_git(["worktree", "add", "-b", name, wt_path], cwd=project_path)
        if wt_result.startswith("ERROR"):
            return [TextContent(type="text", text=wt_result)]
        results.append(f"Worktree: {wt_path}")

        # Verify worktree
        if not os.path.isdir(wt_path):
            return [TextContent(type="text", text=f"ERROR: Worktree not created at {wt_path}")]

        # Copy plugin settings
        settings_src = os.path.join(project_path, ".claude", "settings.local.json")
        if os.path.isfile(settings_src):
            settings_dst_dir = os.path.join(wt_path, ".claude")
            os.makedirs(settings_dst_dir, exist_ok=True)
            import shutil
            shutil.copy2(settings_src, os.path.join(settings_dst_dir, "settings.local.json"))
            results.append("Settings copied.")

        # Symlink venv
        venv_src = os.path.join(project_path, "venv")
        if os.path.isdir(venv_src):
            venv_dst = os.path.join(wt_path, "venv")
            if not os.path.exists(venv_dst):
                os.symlink(venv_src, venv_dst)
                results.append("Venv symlinked.")

        actual_path = wt_path

    # Spawn via tmux
    spawn_output = _run_tmux(
        f'spawn_claude_worker_from_file "workers" "{name}" "{actual_path}" "{model}" "{prompt_file}"'
    )
    if spawn_output.startswith("ERROR"):
        return [TextContent(type="text", text=spawn_output)]

    results.append(f"Session: {spawn_output}")
    results.append(f"Attach: tmux attach -t {spawn_output}")

    return [TextContent(type="text", text="\n".join(results))]


@mcp.tool
def worker_merge(
    name: str,
    project_path: str | None = None
) -> list[TextContent]:
    """Merge worker branch, cleanup worktree + tmux."""
    path = project_path or os.getcwd()
    results = []

    wt_path = os.path.join(path, ".claude", "worktrees", name)

    # Read WORKER_REPORT.md if exists
    report_path = os.path.join(wt_path, "WORKER_REPORT.md")
    report = ""
    if os.path.isfile(report_path):
        with open(report_path) as f:
            report = f.read()
        results.append(f"=== WORKER REPORT ===\n{report}\n=== END REPORT ===")

    # Check commits
    log_output = _run_git(["log", f"main..{name}", "--oneline"], cwd=path)
    if log_output and not log_output.startswith("ERROR"):
        results.append(f"Commits:\n{log_output}")

    # Merge
    merge_result = _run_git(["merge", name], cwd=path)
    if merge_result.startswith("ERROR"):
        results.append(f"Merge failed: {merge_result}")
        return [TextContent(type="text", text="\n\n".join(results))]
    results.append(f"Merged: {merge_result}")

    # Remove WORKER_REPORT.md
    report_in_main = os.path.join(path, "WORKER_REPORT.md")
    if os.path.isfile(report_in_main):
        _run_git(["rm", "-f", "WORKER_REPORT.md"], cwd=path)
        _run_git(["commit", "-m", "cleanup: remove worker report"], cwd=path)

    # Cleanup tmux session
    project_name = os.path.basename(path)
    session_name = f"worker-{project_name}-{name}"
    subprocess.run(["tmux", "kill-session", "-t", session_name],
                    capture_output=True, timeout=10)
    results.append(f"Tmux session killed: {session_name}")

    # Cleanup worktree + branch
    if os.path.isdir(wt_path):
        _run_git(["worktree", "remove", "--force", wt_path], cwd=path)
        results.append(f"Worktree removed: {wt_path}")

    _run_git(["branch", "-d", name], cwd=path)
    results.append(f"Branch deleted: {name}")

    return [TextContent(type="text", text="\n\n".join(results))]


if __name__ == "__main__":
    mcp.run()

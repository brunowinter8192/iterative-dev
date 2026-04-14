# INFRASTRUCTURE
import logging
import os
import subprocess
from typing import Literal

from fastmcp import FastMCP
from mcp.types import TextContent

logger = logging.getLogger(__name__)

mcp = FastMCP("iterative-dev")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TMUX_SPAWN_SH = os.path.join(SCRIPT_DIR, "src", "spawn", "tmux_spawn.sh")


# HELPERS

def _run_tmux(func_call: str) -> str:
    """Source tmux_spawn.sh and run a function."""
    cmd = f'source "{TMUX_SPAWN_SH}" && {func_call}'
    logger.debug("Running tmux: %s", func_call)
    try:
        result = subprocess.run(
            ["bash", "-c", cmd],
            capture_output=True, text=True, timeout=60,
            cwd=os.getcwd()
        )
    except subprocess.TimeoutExpired:
        logger.error("tmux timed out: %s", func_call)
        return "ERROR: tmux command timed out after 60s (worker may not be idle)"
    except OSError as e:
        logger.error("tmux OSError: %s", e)
        return f"ERROR: {e.strerror}"
    if result.returncode != 0:
        logger.error("tmux failed: %s", result.stderr.strip())
        return f"ERROR: {result.stderr.strip()}"
    return result.stdout.strip()


def _run_git(args: list[str], cwd: str | None = None) -> str:
    """Run git command and return stdout."""
    logger.debug("Running: git %s", " ".join(args))
    result = subprocess.run(
        ["git"] + args,
        capture_output=True, text=True, timeout=30,
        cwd=cwd or os.getcwd()
    )
    if result.returncode != 0:
        logger.error("git failed: %s", result.stderr.strip())
        return f"ERROR: {result.stderr.strip()}"
    return result.stdout.strip()


# TOOLS — Workers

@mcp.tool
def worker_send(
    name: str,
    message: str,
    project_path: str | None = None
) -> list[TextContent]:
    """Send message to running worker."""
    path = project_path or os.getcwd()
    cmd = f'source "{TMUX_SPAWN_SH}" && worker_send "{name}" "$_WORKER_MSG" "{path}"'
    logger.debug("Running tmux worker_send: name=%s path=%s", name, path)
    try:
        result = subprocess.run(
            ["bash", "-c", cmd],
            capture_output=True, text=True, timeout=60,
            cwd=os.getcwd(),
            env={**os.environ, "_WORKER_MSG": message}
        )
    except subprocess.TimeoutExpired:
        logger.error("worker_send timed out: %s", name)
        return [TextContent(type="text", text="ERROR: worker_send timed out after 60s")]
    except OSError as e:
        logger.error("worker_send OSError: %s", e)
        return [TextContent(type="text", text=f"ERROR: {e.strerror}")]
    output = result.stdout.strip()
    if result.returncode != 0:
        output = f"ERROR: {result.stderr.strip()}"
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
    logger.info("worker_spawn name=%s model=%s worktree=%s project=%s", name, model, worktree, project_path)
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
def dev_sync(
    project_path: str | None = None
) -> list[TextContent]:
    """Sync dev branch to main without checkout. Uses git update-ref for fast-forward."""
    path = project_path or os.getcwd()
    results = []

    # Verify we're on dev
    current = _run_git(["rev-parse", "--abbrev-ref", "HEAD"], cwd=path).strip()
    if current != "dev":
        return [TextContent(type="text", text=f"ERROR: Not on dev branch (on '{current}'). Switch to dev first.")]

    # Check if main exists, fall back to master
    main_check = _run_git(["rev-parse", "--verify", "main"], cwd=path)
    if main_check.startswith("ERROR"):
        main_check = _run_git(["rev-parse", "--verify", "master"], cwd=path)
        if main_check.startswith("ERROR"):
            return [TextContent(type="text", text="ERROR: Neither 'main' nor 'master' branch found.")]
        main_branch = "master"
    else:
        main_branch = "main"

    # Verify fast-forward (main is ancestor of dev)
    ff_check = subprocess.run(
        ["git", "merge-base", "--is-ancestor", main_branch, "dev"],
        capture_output=True, text=True, timeout=10, cwd=path
    )
    if ff_check.returncode != 0:
        return [TextContent(type="text", text=f"ERROR: {main_branch} is not an ancestor of dev. Cannot fast-forward. Manual merge needed.")]

    # Show what will be synced
    log_output = _run_git(["log", f"{main_branch}..dev", "--oneline"], cwd=path)
    if not log_output or log_output.startswith("ERROR"):
        return [TextContent(type="text", text=f"Nothing to sync — {main_branch} is already up to date with dev.")]
    results.append(f"Commits to sync:\n{log_output}")

    # Update main ref to point to dev HEAD
    dev_hash = _run_git(["rev-parse", "dev"], cwd=path).strip()
    update_result = _run_git(["update-ref", f"refs/heads/{main_branch}", dev_hash], cwd=path)
    if update_result.startswith("ERROR"):
        return [TextContent(type="text", text=f"update-ref failed: {update_result}")]

    results.append(f"Synced: {main_branch} → {dev_hash[:8]}")
    results.append(f"Stay on dev. {main_branch} updated via ref update (no checkout needed).")

    return [TextContent(type="text", text="\n\n".join(results))]


# GIT TOOLS

def _run_git_script(script: str, repo_path: str, extra_args: list[str] | None = None) -> str:
    """Run a src/git script and return stdout."""
    cmd = ["python3", "-m", f"src.git.{script}", repo_path] + (extra_args or [])
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30, cwd=SCRIPT_DIR)
    output = result.stdout.strip()
    if result.returncode != 0 and result.stderr.strip():
        output += f"\nERROR: {result.stderr.strip()}"
    return output


@mcp.tool
def git_check(repo_path: str) -> list[TextContent]:
    """Pre-commit check with auto-staging."""
    return [TextContent(type="text", text=_run_git_script("check", repo_path, ["--auto-stage"]))]


if __name__ == "__main__":
    mcp.run()

# INFRASTRUCTURE
import logging
import os
import subprocess
from pathlib import Path
from typing import Literal

import httpx
from fastmcp import FastMCP
from mcp.types import TextContent

from src.pipeline.list_agents import format_table, list_agents_workflow
from src.pipeline.jsonl_to_md import convert_workflow
from src.pipeline.extract_calls import extract_workflow

logger = logging.getLogger(__name__)

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
    logger.debug("Running: %s", " ".join(cmd))
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        logger.error("bd failed: %s", result.stderr.strip())
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
    bead_title: str,
    description: str,
    type: Literal["task"] = "task",
    labels: str | None = None,
    repo: str | None = None
) -> list[TextContent]:
    """Create a new bead."""
    args = ["create", "--title", bead_title, "--type", type, "--description", description]
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
        except (OSError, ValueError) as e:
            logger.error("Failed to read capture file %s: %s", filepath, e)
    return [TextContent(type="text", text=output)]


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
def worker_merge(
    name: str,
    project_path: str | None = None
) -> list[TextContent]:
    """Merge worker branch into main. Worker stays alive (tmux + worktree preserved)."""
    logger.info("worker_merge name=%s", name)
    path = project_path or os.getcwd()
    results = []

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

    # Worker stays alive — use worker_kill to cleanup later
    results.append(f"Worker '{name}' still alive (tmux + worktree preserved)")

    return [TextContent(type="text", text="\n\n".join(results))]


@mcp.tool
def worker_kill(
    name: str,
    project_path: str | None = None
) -> list[TextContent]:
    """Kill worker: terminate tmux session, remove worktree, delete branch."""
    logger.info("worker_kill name=%s", name)
    path = project_path or os.getcwd()
    results = []

    wt_path = os.path.join(path, ".claude", "worktrees", name)

    # Kill tmux session
    project_name = os.path.basename(path)
    session_name = f"worker-{project_name}-{name}"
    subprocess.run(["tmux", "kill-session", "-t", session_name],
                    capture_output=True, timeout=10)
    results.append(f"Tmux session killed: {session_name}")

    # Remove worktree
    if os.path.isdir(wt_path):
        _run_git(["worktree", "remove", "--force", wt_path], cwd=path)
        results.append(f"Worktree removed: {wt_path}")

    # Delete branch
    _run_git(["branch", "-d", name], cwd=path)
    results.append(f"Branch deleted: {name}")

    return [TextContent(type="text", text="\n\n".join(results))]



# TOOLS — LLM Proxy

NVIDIA_NIM_URL = "https://integrate.api.nvidia.com/v1/chat/completions"
DEFAULT_LLM_MODEL = "mistralai/mistral-large-3-675b-instruct-2512"

MODEL_ALIASES = {
    "gemma": "google/gemma-3-27b-it",
    "mistral": "mistralai/mistral-small-3.1-24b-instruct-2503",
    "mistral-medium": "mistralai/mistral-medium-3-instruct",
    "qwen": "qwen/qwen2.5-72b-instruct",
    "llama": "meta/llama-3.3-70b-instruct",
    "nemotron": "nvidia/llama-3.1-nemotron-70b-instruct",
}


def _call_nim(text: str, model: str, api_key: str) -> str:
    """Call NVIDIA NIM API. Returns response text or raises."""
    resp = httpx.post(
        NVIDIA_NIM_URL,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        json={
            "model": model,
            "messages": [{"role": "user", "content": text}],
            "max_tokens": 4096,
            "temperature": 0.15,
        },
        timeout=300,
    )
    if resp.status_code != 200:
        raise RuntimeError(f"ERROR {resp.status_code}: {resp.text[:500]}")
    content = resp.json().get("choices", [{}])[0].get("message", {}).get("content", "")
    if not content:
        raise RuntimeError(f"ERROR: empty response. Raw: {resp.text[:500]}")
    return content


@mcp.tool
def prompt(
    text: str,
    model: str | None = None,
    input_file: str | None = None,
    output_file: str | None = None,
) -> list[TextContent]:
    """Send a prompt to an external LLM (NVIDIA NIM) and return the response.

    Args:
        text: The prompt/instructions to send. If input_file is set, the file
              content is appended after the prompt text.
        model: Model name — use alias (gemma, mistral, mistral-medium, qwen, llama, nemotron) or full
               NVIDIA NIM model ID. Default: mistral.
        input_file: Optional path to a file to read and append to the prompt.
        output_file: Optional path to write the LLM response to.
    """
    api_key = os.environ.get("NVIDIA_API_KEY", "")
    if not api_key:
        return [TextContent(type="text", text="ERROR: NVIDIA_API_KEY not set")]

    use_model = MODEL_ALIASES.get(model, model) if model else DEFAULT_LLM_MODEL

    full_prompt = text
    if input_file:
        try:
            file_content = Path(input_file).read_text(encoding="utf-8")
            full_prompt = f"{text}\n\n---\n\n{file_content}"
        except FileNotFoundError:
            return [TextContent(type="text", text=f"ERROR: File not found: {input_file}")]

    try:
        content = _call_nim(full_prompt, use_model, api_key)
    except httpx.TimeoutException:
        return [TextContent(type="text", text="ERROR: Request timed out after 120s")]
    except RuntimeError as e:
        return [TextContent(type="text", text=str(e))]

    if output_file:
        out_path = Path(output_file)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(content, encoding="utf-8")
        return [TextContent(type="text", text=f"Written to {output_file} ({len(content)} chars, model: {use_model})")]

    return [TextContent(type="text", text=content)]


# TOOLS — Eval

@mcp.tool
def eval_list_agents(
    project_path: str,
    session: Literal["latest"] | None = None
) -> list[TextContent]:
    """List subagents for a project session."""
    agents = list_agents_workflow(project_path, session=session)
    table = format_table(agents)
    paths = "\n".join(f"{a['agent_id']}: {a['path']}" for a in agents)
    return [TextContent(type="text", text=f"{table}\n\nJSONL paths:\n{paths}")]


@mcp.tool
def eval_extract(
    jsonl_path: str,
    calls: str | None = None
) -> list[TextContent]:
    """Convert agent JSONL to summary, or extract specific tool calls."""
    if calls:
        call_numbers = [int(n.strip()) for n in calls.split(",")]
        content = extract_workflow(jsonl_path, call_numbers)
    else:
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".md", delete=False) as f:
            tmp_path = f.name
        convert_workflow(jsonl_path, tmp_path, include_dispatch=True)
        summary_path = tmp_path.replace(".md", "_summary.md")
        with open(summary_path, "r") as f:
            content = f.read()
        os.unlink(summary_path)
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
    return [TextContent(type="text", text=content)]


if __name__ == "__main__":
    mcp.run()

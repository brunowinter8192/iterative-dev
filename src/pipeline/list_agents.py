# INFRASTRUCTURE
import argparse
import logging
import re
from pathlib import Path

logger = logging.getLogger(__name__)

# From pipeline/jsonl_to_md.py: JSONL parsing and main session derivation
from .jsonl_to_md import load_jsonl, derive_main_session, find_task_anchor

CC_PROJECTS_DIR = Path.home() / '.claude' / 'projects'


# ORCHESTRATOR
def list_agents_workflow(project_path: str, session: str | None = None) -> list[dict]:
    logger.info("list_agents project=%s session=%s", project_path, session)
    cc_project_dir = derive_cc_project_dir(project_path)
    jsonl_paths = find_subagent_jsonls(cc_project_dir)
    agents = []
    for p in jsonl_paths:
        try:
            agents.append(build_agent_info(p))
        except (RuntimeError, FileNotFoundError) as e:
            logger.warning("Skipping agent %s: %s", p.stem, e)
            stat = p.stat()
            agents.append({
                'agent_id': p.stem.replace('agent-', ''),
                'agent_type': 'UNKNOWN (parse error)',
                'session_id': p.parent.parent.name,
                'timestamp': stat.st_mtime,
                'size_kb': stat.st_size / 1024,
                'path': str(p),
            })
    agents.sort(key=lambda a: a['timestamp'], reverse=True)
    if session == 'latest':
        agents = filter_latest_session(agents)
    return agents


# FUNCTIONS

# Convert absolute project path to CC project directory name
def derive_cc_project_dir(project_path: str) -> Path:
    absolute = str(Path(project_path).expanduser().resolve())
    escaped = absolute.replace('/', '-')
    cc_dir = CC_PROJECTS_DIR / escaped
    if not cc_dir.exists():
        raise FileNotFoundError(f"CC project directory not found: {cc_dir}")
    return cc_dir


# Find all subagent JSONL files across all sessions
def find_subagent_jsonls(cc_project_dir: Path) -> list[Path]:
    paths = sorted(cc_project_dir.glob('*/subagents/agent-*.jsonl'))
    if not paths:
        raise FileNotFoundError(f"No subagent JSONLs found in {cc_project_dir}")
    return paths


# Build info dict for a single subagent JSONL
def build_agent_info(jsonl_path: Path) -> dict:
    agent_id = jsonl_path.stem.replace('agent-', '')
    stat = jsonl_path.stat()
    timestamp = stat.st_mtime
    size_kb = stat.st_size / 1024

    main_session_path, _ = derive_main_session(str(jsonl_path))
    main_messages = load_jsonl(main_session_path)

    anchor_idx = find_task_anchor(main_messages, agent_id)
    if anchor_idx is not None:
        agent_type = extract_agent_type(main_messages, anchor_idx, agent_id)
    else:
        agent_type = extract_agent_type_by_result(main_messages, agent_id)

    session_id = jsonl_path.parent.parent.name

    return {
        'agent_id': agent_id,
        'agent_type': agent_type,
        'session_id': session_id,
        'timestamp': timestamp,
        'size_kb': size_kb,
        'path': str(jsonl_path),
    }


# Extract subagent_type from Agent/Task tool_use block before anchor
def extract_agent_type(main_messages: list[dict], anchor_idx: int, agent_id: str) -> str:
    for i in range(anchor_idx, max(-1, anchor_idx - 6), -1):
        msg_wrapper = main_messages[i]
        if 'message' not in msg_wrapper or not isinstance(msg_wrapper.get('message'), dict):
            continue
        content = msg_wrapper['message'].get('content', [])
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict) or block.get('type') != 'tool_use':
                continue
            if block.get('name') not in ('Agent', 'Task'):
                continue
            agent_type = block.get('input', {}).get('subagent_type', '')
            if agent_type:
                return agent_type

    raise RuntimeError(f"Agent {agent_id}: no Agent/Task tool_use found near anchor_idx={anchor_idx}")


# Fallback: find agent_type by matching agentId in tool_result text (async agents)
def extract_agent_type_by_result(main_messages: list[dict], agent_id: str) -> str:
    agent_id_pattern = re.compile(rf'agentId:\s*{re.escape(agent_id)}')

    for msg_wrapper in main_messages:
        if 'message' not in msg_wrapper or not isinstance(msg_wrapper.get('message'), dict):
            continue
        content = msg_wrapper['message'].get('content', [])
        if not isinstance(content, list):
            continue

        for block in content:
            if not isinstance(block, dict) or block.get('type') != 'tool_result':
                continue
            result_content = block.get('content', '')
            if isinstance(result_content, list):
                result_text = ' '.join(str(b.get('text', '')) if isinstance(b, dict) else str(b) for b in result_content)
            else:
                result_text = str(result_content)

            if not agent_id_pattern.search(result_text):
                continue

            tool_use_id = block.get('tool_use_id', '')
            return find_type_by_tool_use_id(main_messages, tool_use_id, agent_id)

    raise RuntimeError(f"Agent {agent_id}: no progress anchor and no async result found in main session")


# Find subagent_type from the Agent/Task tool_use block matching a tool_use_id
def find_type_by_tool_use_id(main_messages: list[dict], tool_use_id: str, agent_id: str) -> str:
    for msg_wrapper in main_messages:
        if 'message' not in msg_wrapper or not isinstance(msg_wrapper.get('message'), dict):
            continue
        content = msg_wrapper['message'].get('content', [])
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict) or block.get('type') != 'tool_use':
                continue
            if block.get('id') != tool_use_id:
                continue
            agent_type = block.get('input', {}).get('subagent_type', '')
            if agent_type:
                return agent_type

    raise RuntimeError(f"Agent {agent_id}: found async result but no matching Agent/Task tool_use for {tool_use_id}")


# Filter agents to only those from the most recent session
def filter_latest_session(agents: list[dict]) -> list[dict]:
    if not agents:
        return []
    latest_session = agents[0]['session_id']
    return [a for a in agents if a['session_id'] == latest_session]


# Format agents list as aligned table string
def format_table(agents: list[dict]) -> str:
    from datetime import datetime
    header = f"{'agent_id':<22} {'agent_type':<40} {'timestamp':<20} {'size':>8}"
    separator = '-' * len(header)
    lines = [header, separator]

    for a in agents:
        ts = datetime.fromtimestamp(a['timestamp']).strftime('%Y-%m-%d %H:%M')
        size = f"{a['size_kb']:.0f}KB"
        lines.append(f"{a['agent_id']:<22} {a['agent_type']:<40} {ts:<20} {size:>8}")

    return '\n'.join(lines)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="List subagents with types for a CC project")
    parser.add_argument("--project", required=True, help="Absolute path to project directory")
    parser.add_argument("--session", choices=["latest"], help="Filter by session (latest = most recent)")
    args = parser.parse_args()

    agents = list_agents_workflow(args.project, session=args.session)
    print(format_table(agents))

# INFRASTRUCTURE
from pathlib import Path

from .jsonl_parse import extract_text_content, strip_system_reminders


# FUNCTIONS

def derive_main_session(subagent_path: str) -> tuple[str, str]:
    p = Path(subagent_path)
    agent_id = p.stem.replace('agent-', '')
    session_dir = p.parent.parent
    main_session = session_dir.with_suffix('.jsonl')
    if not main_session.exists():
        raise FileNotFoundError(f"Main session not found: {main_session}")
    return str(main_session), agent_id


def extract_dispatch_context(main_messages: list[dict], agent_id: str) -> dict:
    anchor_idx = find_task_anchor(main_messages, agent_id)
    if anchor_idx is None:
        return {"pre_messages": [], "dispatch_prompt": "", "post_message": ""}

    task_tool_use_id, dispatch_prompt = find_task_tool_use(main_messages, anchor_idx)
    pre_messages = collect_pre_dispatch(main_messages, anchor_idx)
    post_message = collect_post_dispatch(main_messages, anchor_idx, task_tool_use_id)

    return {
        "pre_messages": pre_messages,
        "dispatch_prompt": strip_system_reminders(dispatch_prompt),
        "post_message": post_message
    }


def find_task_anchor(messages: list[dict], agent_id: str) -> int | None:
    for i, message in enumerate(messages):
        if message.get('type') != 'progress':
            continue
        data = message.get('data', {})
        if isinstance(data, dict) and data.get('agentId') == agent_id:
            return i
    return None


def find_task_tool_use(messages: list[dict], anchor_idx: int) -> tuple[str, str]:
    for i in range(anchor_idx, max(-1, anchor_idx - 6), -1):
        msg_wrapper = messages[i]
        if 'message' not in msg_wrapper or not isinstance(msg_wrapper.get('message'), dict):
            continue
        content = msg_wrapper['message'].get('content', [])
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict) and block.get('type') == 'tool_use' and block.get('name') == 'Agent':
                tool_use_id = block['id']
                prompt = str(block['input']['prompt'])
                return tool_use_id, prompt
    return '', ''


def collect_pre_dispatch(messages: list[dict], anchor_idx: int) -> list[str]:
    pre_messages = []
    for i in range(anchor_idx - 1, max(-1, anchor_idx - 8), -1):
        msg_wrapper = messages[i]
        if 'message' not in msg_wrapper or not isinstance(msg_wrapper.get('message'), dict):
            continue
        msg = msg_wrapper['message']
        role = msg.get('role', '')
        if not role:
            continue
        text = strip_system_reminders(extract_text_content(msg))
        if not text:
            continue
        pre_messages.insert(0, f"**{role}:** {text}")
        if role == 'user':
            break
    return pre_messages


def collect_post_dispatch(messages: list[dict], anchor_idx: int, task_tool_use_id: str) -> str:
    if not task_tool_use_id:
        return ''

    result_idx = None
    for i in range(anchor_idx, len(messages)):
        msg_wrapper = messages[i]
        if 'message' not in msg_wrapper or not isinstance(msg_wrapper.get('message'), dict):
            continue
        content = msg_wrapper['message'].get('content', [])
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict) and block.get('type') == 'tool_result' and block.get('tool_use_id') == task_tool_use_id:
                result_idx = i
                break
        if result_idx is not None:
            break

    if result_idx is None:
        return ''

    for i in range(result_idx + 1, min(len(messages), result_idx + 10)):
        msg_wrapper = messages[i]
        if 'message' not in msg_wrapper or not isinstance(msg_wrapper.get('message'), dict):
            continue
        msg = msg_wrapper['message']
        if msg.get('role') == 'assistant':
            text = strip_system_reminders(extract_text_content(msg))
            if text:
                return text
    return ''


def format_dispatch_context(context: dict) -> str:
    lines = ["# Dispatch Context"]

    if context["pre_messages"]:
        lines.append("\n## Pre-Dispatch\n")
        for msg in context["pre_messages"]:
            lines.append(msg)
            lines.append("")

    if context["post_message"]:
        lines.append("## Post-Dispatch\n")
        lines.append(context["post_message"])

    return '\n'.join(lines)

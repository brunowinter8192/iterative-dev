# INFRASTRUCTURE
import argparse
import json
import re
from pathlib import Path


# ORCHESTRATOR
def convert_workflow(jsonl_path: str, output_path: str, include_dispatch: bool = False) -> int:
    messages = load_jsonl(jsonl_path)
    task_prompt, final_response = extract_session_context(messages)
    tool_calls = extract_tool_calls(messages)

    dispatch_context = None
    if include_dispatch:
        main_session_path, agent_id = derive_main_session(jsonl_path)
        main_messages = load_jsonl(main_session_path)
        dispatch_context = extract_dispatch_context(main_messages, agent_id)

    summary_content = format_summary_markdown(tool_calls, task_prompt, final_response, dispatch_context)
    details_content = format_details_markdown(tool_calls)

    summary_path = str(Path(output_path).with_stem(Path(output_path).stem + '_summary'))
    write_output(summary_path, summary_content)
    write_output(output_path, details_content)
    return len(tool_calls)


# FUNCTIONS

# Load all lines from JSONL file
def load_jsonl(jsonl_path: str) -> list[dict]:
    path = Path(jsonl_path)
    if not path.exists():
        raise FileNotFoundError(f"JSONL not found: {jsonl_path}")

    messages = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                messages.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return messages


# Extract task prompt (first user message) and final response (last assistant text)
def extract_session_context(messages: list[dict]) -> tuple[str, str]:
    task_prompt = ''
    final_response = ''

    for message in messages:
        msg = message.get('message', message)
        role = msg.get('role', '')
        if role == 'user' and not task_prompt:
            task_prompt = extract_text_content(msg)
            break

    for message in reversed(messages):
        msg = message.get('message', message)
        role = msg.get('role', '')
        if role == 'assistant':
            text = extract_text_content(msg)
            if text:
                final_response = text
                break

    return strip_system_reminders(task_prompt), strip_system_reminders(final_response)


# Extract text blocks from a message (ignoring tool_use/tool_result blocks)
def extract_text_content(msg: dict) -> str:
    content = msg.get('content', '')
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        texts = []
        for block in content:
            if isinstance(block, dict) and block.get('type') == 'text':
                texts.append(block.get('text', ''))
            elif isinstance(block, str):
                texts.append(block)
        return '\n'.join(texts)
    return ''


# Extract tool_use and tool_result pairs from messages
def extract_tool_calls(messages: list[dict]) -> list[dict]:
    tool_use_cache = {}
    tool_calls = []

    for message in messages:
        content_blocks = get_content_blocks(message)
        if not content_blocks:
            continue

        for block in content_blocks:
            if block.get('type') == 'tool_use':
                tool_data = {
                    'tool_name': block.get('name', 'Unknown'),
                    'input': block.get('input', {}),
                    'output': None,
                    'tool_use_id': block.get('id', ''),
                    'timestamp': message.get('timestamp', '')
                }
                tool_use_cache[tool_data['tool_use_id']] = tool_data

            elif block.get('type') == 'tool_result':
                tool_use_id = block.get('tool_use_id')
                if tool_use_id in tool_use_cache:
                    tool_data = tool_use_cache[tool_use_id]
                    tool_data['output'] = extract_result_content(block)
                    tool_calls.append(tool_data)
                    del tool_use_cache[tool_use_id]

    return sorted(tool_calls, key=lambda x: x.get('timestamp', ''))


# Get content blocks from message (handles nested structures)
def get_content_blocks(message: dict) -> list[dict]:
    if 'message' in message and isinstance(message['message'], dict):
        content = message['message'].get('content', [])
    else:
        content = message.get('content', [])

    if isinstance(content, list):
        return content
    return []


# Extract text content from tool_result block
def extract_result_content(block: dict) -> str:
    content = block.get('content', '')
    if isinstance(content, list) and len(content) > 0:
        if isinstance(content[0], dict):
            text = content[0].get('text', '')
        else:
            text = str(content[0])
    else:
        text = str(content)

    return strip_system_reminders(text)


# Remove system-reminder tags from content
def strip_system_reminders(content: str) -> str:
    pattern = r'<system-reminder>.*?</system-reminder>'
    return re.sub(pattern, '', content, flags=re.DOTALL).strip()


# Derive main session path and agent ID from subagent JSONL path
def derive_main_session(subagent_path: str) -> tuple[str, str]:
    p = Path(subagent_path)
    agent_id = p.stem.replace('agent-', '')
    session_dir = p.parent.parent
    main_session = session_dir.with_suffix('.jsonl')
    if not main_session.exists():
        raise FileNotFoundError(f"Main session not found: {main_session}")
    return str(main_session), agent_id


# Extract dispatch context from main session for a specific agent
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


# Find first progress line with matching data.agentId
def find_task_anchor(messages: list[dict], agent_id: str) -> int | None:
    for i, message in enumerate(messages):
        if message.get('type') != 'progress':
            continue
        data = message.get('data', {})
        if isinstance(data, dict) and data.get('agentId') == agent_id:
            return i
    return None


# Find Agent tool_use block before anchor (closest one, searching backwards)
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
                tool_use_id = block.get('id', '')
                prompt = str(block.get('input', {}).get('prompt', ''))
                return tool_use_id, prompt
    return '', ''


# Collect 2-3 pre-dispatch messages (assistant reasoning + user context)
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


# Collect post-dispatch message (how main processed the result)
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


# Format dispatch context as markdown section
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


# Format summary MD (dispatch context, task prompt, summary table, final response)
def format_summary_markdown(tool_calls: list[dict], task_prompt: str, final_response: str,
                            dispatch_context: dict = None) -> str:
    sections = []

    if dispatch_context:
        sections.append(format_dispatch_context(dispatch_context))

    if task_prompt:
        sections.append(f"# Task Prompt\n\n{task_prompt}")

    sections.append(format_summary_table(tool_calls))

    if final_response:
        sections.append(f"# Final Response\n\n{final_response}")

    return '\n\n---\n\n'.join(sections)


# Format details MD (only tool call sections, for RAG indexing)
def format_details_markdown(tool_calls: list[dict]) -> str:
    sections = []
    for i, call in enumerate(tool_calls, 1):
        sections.append(format_tool_call(call, i))
    return '\n\n---\n\n'.join(sections)


# Format compact summary table of all tool calls
def format_summary_table(tool_calls: list[dict]) -> str:
    rows = ["# Tool Call Summary", "",
            "| # | Tool | Input | Output Size |",
            "|---|------|-------|-------------|"]

    for i, call in enumerate(tool_calls, 1):
        tool = call['tool_name']
        brief = format_input_brief(call['input'])
        output = call.get('output') or ''
        size = len(output)
        rows.append(f"| {i} | {tool} | {brief} | {size} chars |")

    return '\n'.join(rows)


# Format input as brief one-liner for summary table
def format_input_brief(input_data: dict, max_len: int = 80) -> str:
    if not input_data or not isinstance(input_data, dict):
        return '(no input)'

    if 'command' in input_data:
        val = str(input_data['command'])
    elif 'file_path' in input_data:
        val = str(input_data['file_path'])
    elif 'pattern' in input_data:
        val = str(input_data['pattern'])
    elif 'query' in input_data:
        val = str(input_data['query'])
    else:
        val = str(list(input_data.values())[0])

    if len(val) > max_len:
        val = val[:max_len - 3] + '...'
    return val


# Format single tool call detail section
def format_tool_call(call: dict, index: int) -> str:
    tool_name = call['tool_name']
    input_str = format_input(call['input'])
    output = call['output'] or '(no output)'

    return f"""# Tool Call {index}: {tool_name}

**Input:**
{input_str}

**Output:**
{output}"""


# Format input dict as readable string
def format_input(input_data: dict) -> str:
    if not input_data:
        return '(no input)'

    if not isinstance(input_data, dict):
        return str(input_data)

    parts = []
    for key, value in input_data.items():
        value_str = str(value)
        if len(value_str) > 500:
            value_str = value_str[:500] + '...'
        parts.append(f"- {key}: {value_str}")

    return '\n'.join(parts)


# Write content to output file
def write_output(output_path: str, content: str) -> None:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert Claude Code JSONL to Markdown")
    parser.add_argument("--input", required=True, help="Path to JSONL file")
    parser.add_argument("--output", required=True, help="Path for output MD file")
    parser.add_argument("--dispatch", action="store_true",
                        help="Include dispatch context from main session")

    args = parser.parse_args()
    count = convert_workflow(args.input, args.output, include_dispatch=args.dispatch)
    summary_path = str(Path(args.output).with_stem(Path(args.output).stem + '_summary'))
    print(f"Converted {count} tool calls to {args.output} + {summary_path}")

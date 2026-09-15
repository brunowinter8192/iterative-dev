# INFRASTRUCTURE
import json
import re
from pathlib import Path


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


# Check if tool_result contains an error (tool_use_error tag or is_error flag)
def is_tool_error(block: dict) -> bool:
    if block.get('is_error'):
        return True
    content = block.get('content', '')
    if isinstance(content, list) and len(content) > 0:
        first = content[0]
        text = first.get('text', '') if isinstance(first, dict) else str(first)
    else:
        text = str(content)
    return '<tool_use_error>' in text or 'No such tool available' in text


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
                    tool_data['is_error'] = is_tool_error(block)
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

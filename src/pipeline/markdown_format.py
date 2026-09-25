# INFRASTRUCTURE
import re
from datetime import datetime
from pathlib import Path

from .dispatch_context import format_dispatch_context

CONTENT_PARAM_KEYS = {'content', 'file_content', 'new_string'}


# FUNCTIONS

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


def format_summary_table(tool_calls: list[dict]) -> str:
    lines = ["# Tool Call Summary", ""]

    for i, call in enumerate(tool_calls, 1):
        tool = call['tool_name']
        ts = format_timestamp(call.get('timestamp', ''))
        params = format_input_params(call['input'])
        output = call.get('output') or ''
        if call.get('is_error'):
            error_text = re.sub(r'</?tool_use_error>', '', output).strip()
            if len(error_text) > 60:
                error_text = error_text[:60] + '...'
            size_label = f"[error: {error_text}]"
        else:
            size = len(output)
            if size == 0:
                size_label = "[no output]"
            elif size < 500 and tool.startswith('mcp__'):
                size_label = f"[suspicious: {size} chars]"
            else:
                size_label = f"[{size} chars]"
        lines.append(f"[{ts}] #{i} {tool}: {params}  {size_label}")

    return '\n'.join(lines)


def format_timestamp(ts: str) -> str:
    if not ts:
        return '??:??:??'
    dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
    local_dt = dt.astimezone()
    return local_dt.strftime('%H:%M:%S')


def is_file_content_param(key: str, value: str) -> bool:
    if key in CONTENT_PARAM_KEYS and len(value) > 200:
        return True
    if key == 'command' and ('<<' in value or 'cat >' in value) and len(value) > 200:
        return True
    return False


def format_input_params(input_data: dict) -> str:
    if not input_data or not isinstance(input_data, dict):
        return '(no input)'

    parts = []
    for key, value in input_data.items():
        value_str = str(value)
        if is_file_content_param(key, value_str):
            value_str = f'[{len(value_str)} chars]'
        elif len(value_str) > 100:
            value_str = value_str[:100] + '...'
        value_str = value_str.replace('\n', ' ')
        parts.append(f"{key}={value_str}")

    return ', '.join(parts)


def format_tool_call(call: dict, index: int) -> str:
    tool_name = call['tool_name']
    input_str = format_input(call['input'])
    output = call['output'] or '(no output)'

    return f"""# Tool Call {index}: {tool_name}

**Input:**
{input_str}

**Output:**
{output}"""


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


def write_output(output_path: str, content: str) -> None:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

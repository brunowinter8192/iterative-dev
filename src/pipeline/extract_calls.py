# INFRASTRUCTURE
import argparse
import logging

from .jsonl_to_md import load_jsonl, extract_tool_calls, format_tool_call, write_output, format_summary_table

logger = logging.getLogger(__name__)


# ORCHESTRATOR
def extract_workflow(jsonl_path: str, call_numbers: list[int], output_path: str | None = None) -> str:
    logger.info("extract_workflow input=%s calls=%s", jsonl_path, call_numbers)
    messages = load_jsonl(jsonl_path)
    tool_calls = extract_tool_calls(messages)

    selected = []
    for n in call_numbers:
        if 1 <= n <= len(tool_calls):
            selected.append((n, tool_calls[n - 1]))

    content = format_extracted(selected)

    if output_path:
        write_output(output_path, content)

    return content


# FUNCTIONS

# Format selected tool calls as markdown
def format_extracted(selected: list[tuple[int, dict]]) -> str:
    sections = []
    for index, call in selected:
        sections.append(format_tool_call(call, index))
    return '\n\n---\n\n'.join(sections)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract specific tool calls from Claude Code JSONL")
    parser.add_argument("--input", required=True, help="Path to subagent JSONL file")
    parser.add_argument("--calls", required=True, help="Comma-separated tool call numbers (e.g., 1,3,7)")
    parser.add_argument("--output", help="Output MD file path (default: stdout)")
    parser.add_argument("--list", action="store_true", help="List all tool calls (summary) instead of extracting")

    args = parser.parse_args()

    if args.list:
        messages = load_jsonl(args.input)
        tool_calls = extract_tool_calls(messages)
        print(format_summary_table(tool_calls))
    else:
        numbers = [int(n.strip()) for n in args.calls.split(",")]
        result = extract_workflow(args.input, numbers, args.output)
        if not args.output:
            print(result)

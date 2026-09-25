# INFRASTRUCTURE
import argparse
import logging

from src.pipeline.jsonl_parse import load_jsonl, extract_tool_calls
from src.pipeline.markdown_format import format_tool_call, format_summary_table, write_output

logger = logging.getLogger(__name__)


# ORCHESTRATOR

def extract_workflow() -> None:
    args = parse_args()
    logger.info("extract_workflow input=%s calls=%s list=%s", args.input, args.calls, args.list)
    messages = load_jsonl(args.input)
    tool_calls = extract_tool_calls(messages)
    if args.list:
        print(format_summary_table(tool_calls))
        return
    selected = select_calls(tool_calls, parse_call_numbers(args.calls))
    content = format_extracted(selected)
    if args.output:
        write_output(args.output, content)
    else:
        print(content)


# FUNCTIONS

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Extract specific tool calls from Claude Code JSONL")
    parser.add_argument("--input", required=True, help="Path to subagent JSONL file")
    parser.add_argument("--calls", required=True, help="Comma-separated tool call numbers (e.g., 1,3,7)")
    parser.add_argument("--output", help="Output MD file path (default: stdout)")
    parser.add_argument("--list", action="store_true", help="List all tool calls (summary) instead of extracting")
    return parser.parse_args()


def parse_call_numbers(calls: str) -> list[int]:
    return [int(n.strip()) for n in calls.split(",")]


def select_calls(tool_calls: list[dict], call_numbers: list[int]) -> list[tuple[int, dict]]:
    selected = []
    for n in call_numbers:
        if 1 <= n <= len(tool_calls):
            selected.append((n, tool_calls[n - 1]))
    return selected


def format_extracted(selected: list[tuple[int, dict]]) -> str:
    sections = []
    for index, call in selected:
        sections.append(format_tool_call(call, index))
    return '\n\n---\n\n'.join(sections)


if __name__ == "__main__":
    extract_workflow()

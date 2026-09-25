# INFRASTRUCTURE
import argparse
import logging
from pathlib import Path

from src.pipeline.jsonl_parse import load_jsonl, extract_session_context, extract_tool_calls
from src.pipeline.dispatch_context import derive_main_session, extract_dispatch_context
from src.pipeline.markdown_format import format_summary_markdown, write_output

logger = logging.getLogger(__name__)


# ORCHESTRATOR

def convert_workflow() -> None:
    args = parse_args()
    logger.info("convert_workflow input=%s output=%s dispatch=%s", args.input, args.output, args.dispatch)
    messages = load_jsonl(args.input)
    task_prompt, final_response = extract_session_context(messages)
    tool_calls = extract_tool_calls(messages)
    dispatch_context = None
    if args.dispatch:
        dispatch_context = load_dispatch_context(args.input)
    summary_content = format_summary_markdown(tool_calls, task_prompt, final_response, dispatch_context)
    summary_path = summary_output_path(args.output)
    write_output(summary_path, summary_content)
    report_conversion(len(tool_calls), summary_path)


# FUNCTIONS

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert Claude Code JSONL to Markdown")
    parser.add_argument("--input", required=True, help="Path to JSONL file")
    parser.add_argument("--output", required=True, help="Path for output MD file")
    parser.add_argument("--dispatch", action="store_true",
                        help="Include dispatch context from main session")
    return parser.parse_args()


def load_dispatch_context(jsonl_path: str) -> dict:
    main_session_path, agent_id = derive_main_session(jsonl_path)
    main_messages = load_jsonl(main_session_path)
    return extract_dispatch_context(main_messages, agent_id)


def summary_output_path(output_path: str) -> str:
    return str(Path(output_path).with_stem(Path(output_path).stem + '_summary'))


def report_conversion(count: int, summary_path: str) -> None:
    print(f"Converted {count} tool calls to {summary_path}")


if __name__ == "__main__":
    convert_workflow()

# INFRASTRUCTURE
import argparse
import logging
from pathlib import Path

from .jsonl_parse import load_jsonl, extract_session_context, extract_tool_calls
from .dispatch_context import derive_main_session, extract_dispatch_context
from .markdown_format import format_summary_markdown, write_output

logger = logging.getLogger(__name__)


# ORCHESTRATOR
def convert_workflow(jsonl_path: str, output_path: str, include_dispatch: bool = False) -> int:
    logger.info("convert_workflow input=%s output=%s dispatch=%s", jsonl_path, output_path, include_dispatch)
    messages = load_jsonl(jsonl_path)
    task_prompt, final_response = extract_session_context(messages)
    tool_calls = extract_tool_calls(messages)

    dispatch_context = None
    if include_dispatch:
        main_session_path, agent_id = derive_main_session(jsonl_path)
        main_messages = load_jsonl(main_session_path)
        dispatch_context = extract_dispatch_context(main_messages, agent_id)

    summary_content = format_summary_markdown(tool_calls, task_prompt, final_response, dispatch_context)

    summary_path = str(Path(output_path).with_stem(Path(output_path).stem + '_summary'))
    write_output(summary_path, summary_content)
    return len(tool_calls)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert Claude Code JSONL to Markdown")
    parser.add_argument("--input", required=True, help="Path to JSONL file")
    parser.add_argument("--output", required=True, help="Path for output MD file")
    parser.add_argument("--dispatch", action="store_true",
                        help="Include dispatch context from main session")

    args = parser.parse_args()
    count = convert_workflow(args.input, args.output, include_dispatch=args.dispatch)
    summary_path = str(Path(args.output).with_stem(Path(args.output).stem + '_summary'))
    print(f"Converted {count} tool calls to {summary_path}")

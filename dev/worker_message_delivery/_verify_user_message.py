# INFRASTRUCTURE

import json
import re
import sys

PASTED_PATTERN = re.compile(
    r'<pasted_content id="[0-9a-f]+">\n?(.*?)\n?</pasted_content id="[0-9a-f]+">\n?',
    re.DOTALL,
)

# ORCHESTRATOR

def verify_user_message_workflow():
    jsonl_path, expected_file = _parse_argv()
    expected = _read_expected(expected_file)
    texts = load_user_texts(jsonl_path)
    actual_dewrapped, match = _compare_last_entry(texts, expected)
    _print_result(len(texts), match, expected, actual_dewrapped)
    sys.exit(_exit_code(len(texts), match))

# FUNCTIONS

def _parse_argv():
    return sys.argv[1], sys.argv[2]


def _read_expected(expected_file):
    with open(expected_file) as f:
        return f.read()


def load_user_texts(jsonl_path):
    texts = []
    with open(jsonl_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if record.get("type") != "user":
                continue
            content = record.get("message", {}).get("content")
            if isinstance(content, list):
                content = "".join(
                    block.get("text", "") for block in content if isinstance(block, dict)
                )
            texts.append(content or "")
    return texts


def dewrap(content):
    return PASTED_PATTERN.sub(lambda m: m.group(1), content)


def _compare_last_entry(texts, expected):
    if len(texts) < 1:
        return "", False
    actual_dewrapped = dewrap(texts[-1])
    return actual_dewrapped, actual_dewrapped.strip() == expected.strip()


def _print_result(count, match, expected, actual_dewrapped):
    print(f"USER_ENTRY_COUNT={count}")
    print(f"MATCH={'yes' if match else 'no'}")
    print(f"EXPECTED_LEN={len(expected)}")
    print(f"ACTUAL_LEN={len(actual_dewrapped)}")
    print(f"ACTUAL_HEAD={actual_dewrapped[:60]!r}")
    print(f"ACTUAL_TAIL={actual_dewrapped[-60:]!r}")


def _exit_code(count, match):
    return 0 if (count == 1 and match) else 1


if __name__ == "__main__":
    verify_user_message_workflow()

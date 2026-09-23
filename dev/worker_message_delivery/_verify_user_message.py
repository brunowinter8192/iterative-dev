import json
import re
import sys

PASTED_PATTERN = re.compile(
    r'<pasted_content id="[0-9a-f]+">\n?(.*?)\n?</pasted_content id="[0-9a-f]+">\n?',
    re.DOTALL,
)


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


def main():
    jsonl_path, expected_file = sys.argv[1], sys.argv[2]
    with open(expected_file) as f:
        expected = f.read()
    texts = load_user_texts(jsonl_path)
    count = len(texts)
    match = False
    actual_dewrapped = ""
    if count >= 1:
        actual_dewrapped = dewrap(texts[-1])
        match = actual_dewrapped.strip() == expected.strip()
    print(f"USER_ENTRY_COUNT={count}")
    print(f"MATCH={'yes' if match else 'no'}")
    print(f"EXPECTED_LEN={len(expected)}")
    print(f"ACTUAL_LEN={len(actual_dewrapped)}")
    print(f"ACTUAL_HEAD={actual_dewrapped[:60]!r}")
    print(f"ACTUAL_TAIL={actual_dewrapped[-60:]!r}")
    sys.exit(0 if (count == 1 and match) else 1)


if __name__ == "__main__":
    main()

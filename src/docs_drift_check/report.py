# INFRASTRUCTURE
import datetime
from pathlib import Path

# FUNCTIONS

def print_report(root: Path, sections: list[tuple[str, list[str]]]) -> None:
    print(f"# Docs Drift Check - {datetime.datetime.now().isoformat(timespec='seconds')}")
    print(f"\nProject root: {root}")
    for title, findings in sections:
        _print_section(title, findings)

def exit_code(sections: list[tuple[str, list[str]]]) -> int:
    return 1 if any(findings for _, findings in sections) else 0

def _print_section(title: str, findings: list[str]) -> None:
    print(f"\n## {title} ({len(findings)} findings)\n")
    if not findings:
        print("None.")
    for finding in findings:
        print(f"- {finding}")

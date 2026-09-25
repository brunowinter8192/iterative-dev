# INFRASTRUCTURE
import datetime
from pathlib import Path

# FUNCTIONS

def print_report(
    root: Path,
    path_findings: list[str],
    loc_findings: list[str],
    rule_findings: list[str],
) -> None:
    print(f"# Docs Drift Check - {datetime.datetime.now().isoformat(timespec='seconds')}")
    print(f"\nProject root: {root}")
    _print_section("Path-Drift", path_findings, "None - all paths exist.")
    _print_section("LOC-Drift", loc_findings, "None - all LOC counts equal wc -l.")
    _print_section("Rule-Violation", rule_findings, "None - no function-level or constant references.")

def exit_code(path_findings: list[str], loc_findings: list[str], rule_findings: list[str]) -> int:
    return 1 if path_findings or loc_findings or rule_findings else 0

def _print_section(title: str, findings: list[str], empty_message: str) -> None:
    print(f"\n## {title} ({len(findings)} findings)\n")
    if not findings:
        print(empty_message)
    for finding in findings:
        print(f"- {finding}")

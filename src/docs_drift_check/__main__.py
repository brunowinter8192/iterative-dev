# INFRASTRUCTURE
import sys

from src.docs_drift_check.check_loc import check_loc_drift
from src.docs_drift_check.check_paths import check_path_existence
from src.docs_drift_check.check_rules import check_rule_violations
from src.docs_drift_check.collect import collect_doc_files, collect_source_files
from src.docs_drift_check.project_root import resolve_root
from src.docs_drift_check.report import exit_code, print_report
from src.docs_drift_check.symbols import build_symbol_index

# ORCHESTRATOR

def main() -> int:
    root = resolve_root()
    doc_files = collect_doc_files(root)
    source_files = collect_source_files(root)
    functions, constants, owners = build_symbol_index(source_files)
    path_findings = check_path_existence(doc_files, root, owners)
    loc_findings = check_loc_drift(doc_files, root)
    rule_findings = check_rule_violations(doc_files, root, functions, constants, owners)
    print_report(root, path_findings, loc_findings, rule_findings)
    return exit_code(path_findings, loc_findings, rule_findings)

if __name__ == "__main__":
    sys.exit(main())

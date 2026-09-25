# INFRASTRUCTURE
import sys

from src.docs_drift_check.check_called_by import check_called_by
from src.docs_drift_check.check_directories import check_module_directories
from src.docs_drift_check.check_issues import check_issue_references
from src.docs_drift_check.check_modules import check_module_headings
from src.docs_drift_check.check_rules import check_constant_references, check_function_references
from src.docs_drift_check.check_template import check_titles, check_word_limits
from src.docs_drift_check.collect import collect_doc_files, collect_path_suffixes, collect_source_files
from src.docs_drift_check.project_root import reject_arguments, require_git_repo, resolve_root
from src.docs_drift_check.report import exit_code, print_report
from src.docs_drift_check.symbols import build_symbol_index

RULE_MODULE_HEADINGS = "Rule: module heading is '### <file> (<N> LOC)', file in the same directory, LOC equals wc -l"
RULE_MODULE_DIRECTORIES = "Rule: one DOCS.md per module directory (.py or .sh files), each naming modules of its own directory"
RULE_TITLE = "Rule: title is '# <dir>/'"
RULE_FUNCTIONS = "Rule: no function-level references"
RULE_CONSTANTS = "Rule: no constant references (environment variables and CLI flags excepted)"
RULE_WORD_LIMITS = "Rule: word limits (Role 50, Purpose 25)"
RULE_CALLED_BY = "Rule: Called by is not empty and names existing files"
RULE_ISSUES = "Rule: no references to issues"

# ORCHESTRATOR

def main() -> int:
    reject_arguments(sys.argv[1:])
    root = resolve_root()
    require_git_repo(root)
    doc_files = collect_doc_files(root)
    source_files = collect_source_files(root)
    path_suffixes = collect_path_suffixes(root)
    functions, constants, owners = build_symbol_index(source_files)
    sections = [
        (RULE_MODULE_HEADINGS, check_module_headings(doc_files, root)),
        (RULE_MODULE_DIRECTORIES, check_module_directories(doc_files, source_files, root)),
        (RULE_TITLE, check_titles(doc_files, root)),
        (RULE_FUNCTIONS, check_function_references(doc_files, root, functions, owners)),
        (RULE_CONSTANTS, check_constant_references(doc_files, root, constants)),
        (RULE_WORD_LIMITS, check_word_limits(doc_files, root)),
        (RULE_CALLED_BY, check_called_by(doc_files, root, path_suffixes)),
        (RULE_ISSUES, check_issue_references(doc_files, root)),
    ]
    print_report(root, sections)
    return exit_code(sections)

if __name__ == "__main__":
    sys.exit(main())

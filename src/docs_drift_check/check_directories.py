# INFRASTRUCTURE
from pathlib import Path

from src.docs_drift_check.collect import relative_dir_label
from src.docs_drift_check.markdown_scan import iter_module_headings

# FUNCTIONS

def check_module_directories(doc_files: list[Path], source_files: list[Path], root: Path) -> list[str]:
    findings = _docs_without_modules(doc_files, root)
    findings.extend(_directories_without_docs(doc_files, source_files, root))
    return findings

def _docs_without_modules(doc_files: list[Path], root: Path) -> list[str]:
    findings: list[str] = []
    for doc in doc_files:
        if not any((doc.parent / name).is_file() for name in _heading_names(doc)):
            findings.append(f"`{doc.relative_to(root).as_posix()}` has no module heading naming a file in its own directory")
    return findings

def _heading_names(doc: Path) -> list[str]:
    return [tokens[0] for _, line in iter_module_headings(doc) if (tokens := line[4:].split())]

def _directories_without_docs(doc_files: list[Path], source_files: list[Path], root: Path) -> list[str]:
    documented = {doc.parent for doc in doc_files}
    module_dirs = sorted({source.parent for source in source_files})
    return [
        f"`{relative_dir_label(directory, root)}` holds .py or .sh modules but has no DOCS.md"
        for directory in module_dirs
        if directory not in documented
    ]

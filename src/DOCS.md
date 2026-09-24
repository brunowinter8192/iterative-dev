# src/

Source modules for the iterative-dev plugin infrastructure.

## Documentation Tree

- [spawn/DOCS.md](spawn/DOCS.md) — Worker spawning (tmux_spawn.sh + spawn.py)
- [git/DOCS.md](git/DOCS.md) — Git automation utilities (pre-commit, commit, staging, post-commit)
- [pipeline/DOCS.md](pipeline/DOCS.md) — Session JSONL analysis (conversion, listing, extraction)
- [poread_cli/DOCS.md](poread_cli/DOCS.md) — poread CLI (full-content export marker minting, cross-repo half with monitor-cc's inject_poread.py)
- [docs_drift_check/DOCS.md](docs_drift_check/DOCS.md) — docs-drift-check CLI (DOCS.md rule checks: paths, LOC, function/constant references)

## Directory Map

| Subdir | Role | LOC | Modules |
|---|---|---:|---:|
| spawn/ | Worker spawning and orchestration | 1124 | 3 (tmux_spawn.sh, _capture_clean.py, spawn.py) |
| git/ | Git automation utilities | 446 | 4 (check.py, commit.py, staged.py, post.py) |
| pipeline/ | Session JSONL analysis | 670 | 6 (jsonl_to_md.py, jsonl_parse.py, dispatch_context.py, markdown_format.py, list_agents.py, extract_calls.py) |
| poread_cli/ | poread CLI (marker-minting half) | 77 | 1 (__main__.py) |
| docs_drift_check/ | docs-drift-check CLI | 349 | 10 (__main__.py, collect.py, symbols.py, check_paths.py, check_loc.py, check_rules.py, markdown_scan.py, report.py, project_root.py, config.py) |

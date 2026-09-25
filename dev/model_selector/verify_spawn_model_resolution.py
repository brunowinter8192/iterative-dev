# INFRASTRUCTURE
import importlib.util
import json
import sys
import tempfile
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from dev.strand_runner import run_strands

# ORCHESTRATOR

def verify_spawn_model_resolution_workflow() -> int:
    cases = {
        "missing_config": case_missing_config,
        "valid_config": case_valid_config,
        "malformed_config": case_malformed_config,
        "missing_key_config": case_missing_key_config,
        "model_arg_rejected": case_model_arg_rejected,
        "model_from_config": case_model_from_config,
    }
    code, outputs = run_strands(cases, sys.argv[1:])
    if code == 0 and len(outputs) == len(cases):
        _write_report(_report_lines(outputs))
    return code

# FUNCTIONS

def _load_spawn_module():
    spec_path = REPO_ROOT / "src" / "spawn" / "spawn.py"
    spec = importlib.util.spec_from_file_location("spawn_under_test", spec_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def case_missing_config() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        print(_verify_missing_config_file(_load_spawn_module(), tmp))


def case_valid_config() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        print(_verify_valid_config_file(_load_spawn_module(), tmp)[0])


def case_malformed_config() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        print(_verify_malformed_config_file(_load_spawn_module(), tmp))


def case_missing_key_config() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        print(_verify_missing_key_config_file(_load_spawn_module(), tmp))


def case_model_arg_rejected() -> None:
    print(_verify_model_arg_rejected(_load_spawn_module()))


def case_model_from_config() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        spawn = _load_spawn_module()
        _, valid_path = _verify_valid_config_file(spawn, tmp)
        print("\n".join(_verify_model_from_config(spawn, valid_path)))


def _report_lines(outputs: dict) -> list[str]:
    lines = [f"# spawn.py model-resolution verification — {datetime.now().isoformat(timespec='seconds')}", ""]
    for name in ("missing_config", "valid_config", "malformed_config", "missing_key_config"):
        lines.append(outputs[name].strip())
    lines.append("")
    lines.append("## argparse (real parser)")
    lines.append(outputs["model_arg_rejected"].strip())
    lines.append(outputs["model_from_config"].strip())
    lines.append("")
    lines.append("RESULT: PASS — _resolve_worker_model correct for valid/missing/missing-key config, aborts "
                 "on a malformed config; the real parser accepts no model argument, so the model always comes from "
                 "the config and is a concrete non-empty string.")
    return lines


def _verify_missing_config_file(spawn, tmp) -> str:
    missing_path = Path(tmp) / "does_not_exist.json"
    spawn._MODEL_SELECTION_FILE = str(missing_path)
    resolved = spawn._resolve_worker_model()
    line = f"Missing config file -> {resolved!r} (expected hardcoded fallback)"
    assert resolved == spawn._DEFAULT_WORKER_MODEL
    return line


def _verify_valid_config_file(spawn, tmp):
    valid_path = Path(tmp) / "valid.json"
    valid_path.write_text(json.dumps({"main": "claude-opus-5", "worker": "claude-fable-5"}))
    spawn._MODEL_SELECTION_FILE = str(valid_path)
    resolved = spawn._resolve_worker_model()
    line = f"Valid config -> {resolved!r} (expected config's worker model)"
    assert resolved == "claude-fable-5"
    return line, valid_path


def _verify_malformed_config_file(spawn, tmp) -> str:
    malformed_path = Path(tmp) / "malformed.json"
    malformed_path.write_text("{not valid json")
    spawn._MODEL_SELECTION_FILE = str(malformed_path)
    try:
        resolved = spawn._resolve_worker_model()
    except json.JSONDecodeError as error:
        assert "Expecting property name" in str(error)
        return f"Malformed JSON -> aborts with JSONDecodeError: {error} (expected abort, no fallback)"
    raise AssertionError(f"malformed config must abort, got {resolved!r}")


def _verify_missing_key_config_file(spawn, tmp) -> str:
    missing_key_path = Path(tmp) / "missing_key.json"
    missing_key_path.write_text(json.dumps({"main": "claude-opus-5"}))
    spawn._MODEL_SELECTION_FILE = str(missing_key_path)
    resolved = spawn._resolve_worker_model()
    line = f"Config missing 'worker' key -> {resolved!r} (expected hardcoded fallback)"
    assert resolved == spawn._DEFAULT_WORKER_MODEL
    return line


def _verify_model_arg_rejected(spawn) -> str:
    sys.argv = ["spawn.py", "name", "/prompt", "/project", "claude-explicit-cli-arg"]
    try:
        spawn.parse_args()
    except SystemExit as exit_signal:
        assert exit_signal.code == 2
        return "Fourth positional (model) given to the real parser -> exit 2 (expected rejection, no model argument exists)"
    raise AssertionError("parser must reject a model argument")


def _verify_model_from_config(spawn, valid_path) -> list[str]:
    sys.argv = ["spawn.py", "name", "/prompt", "/project"]
    args = spawn.parse_args()
    lines = [f"Real parser without model -> hasattr(args, 'model')={hasattr(args, 'model')} (expected False)"]
    assert not hasattr(args, "model")
    spawn._MODEL_SELECTION_FILE = str(valid_path)
    resolved_model = spawn._resolve_worker_model()
    lines.append(f"Resolved model -> {resolved_model!r} (expected config's worker model)")
    assert resolved_model == "claude-fable-5"
    assert isinstance(resolved_model, str) and resolved_model
    return lines


def _write_report(lines) -> None:
    report_dir = REPO_ROOT / "dev" / "model_selector" / "md"
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / "verify_spawn_model_resolution.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))


if __name__ == "__main__":
    sys.exit(verify_spawn_model_resolution_workflow())

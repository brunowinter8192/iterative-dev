# INFRASTRUCTURE

import contextlib
import io
import time
import traceback
from concurrent.futures import ProcessPoolExecutor

# ORCHESTRATOR

def run_strands(cases: dict, selected: list) -> tuple[int, dict]:
    names = selected or list(cases)
    with ProcessPoolExecutor(max_workers=len(names)) as pool:
        futures = {name: pool.submit(_run_one, cases[name]) for name in names}
        results = {name: future.result() for name, future in futures.items()}
    outputs = _print_report(names, results)
    failed = [name for name in names if not results[name][0]]
    return (1 if failed else 0), outputs

# FUNCTIONS

def _run_one(case) -> tuple[bool, str, float]:
    buffer = io.StringIO()
    started = time.time()
    ok = True
    with contextlib.redirect_stdout(buffer), contextlib.redirect_stderr(buffer):
        try:
            case()
        except BaseException:
            ok = False
            traceback.print_exc()
    return ok, buffer.getvalue(), time.time() - started

def _print_report(names: list, results: dict) -> dict:
    outputs = {}
    for name in names:
        ok, output, elapsed = results[name]
        print(f"--- strand {name}: {'PASS' if ok else 'FAIL'}, {elapsed:.1f}s ---")
        print(output, end="" if output.endswith("\n") or not output else "\n")
        outputs[name] = output
    passed = sum(1 for name in names if results[name][0])
    print(f"=== {len(names)} strands: {passed} passed, {len(names) - passed} failed ===")
    return outputs

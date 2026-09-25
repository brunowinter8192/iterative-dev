# INFRASTRUCTURE
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PROJECT_SUFFIX = 'my_proj/.claude/worktrees/wt_a'
ENCODED_SUFFIX = 'my-proj--claude-worktrees-wt-a'
SESSION_ID = 'sess1'
AGENT_ID = 'abc123'
AGENT_TYPE = 'fake-type'


# ORCHESTRATOR

def test_workflow() -> None:
    with tempfile.TemporaryDirectory(dir='/tmp') as tmp:
        root = Path(tmp).resolve()
        project = root / 'home' / PROJECT_SUFFIX
        project.mkdir(parents=True)
        fake_home = root / 'fakehome'
        build_fake_tree(fake_home / '.claude' / 'projects' / encode_expected(root / 'home'))
        result = run_list_agents(fake_home, project)
        assert_output(result)


# FUNCTIONS

def encode_expected(home_dir: Path) -> str:
    return str(home_dir).replace('/', '-').replace('.', '-').replace('_', '-') + '-' + ENCODED_SUFFIX


def build_fake_tree(cc_dir: Path) -> None:
    subagents = cc_dir / SESSION_ID / 'subagents'
    subagents.mkdir(parents=True)
    (subagents / f'agent-{AGENT_ID}.jsonl').write_text(json.dumps({'type': 'user'}) + '\n')
    tool_use = {'message': {'role': 'assistant', 'content': [
        {'type': 'tool_use', 'name': 'Agent', 'id': 't1',
         'input': {'subagent_type': AGENT_TYPE, 'prompt': 'p'}}]}}
    progress = {'type': 'progress', 'data': {'agentId': AGENT_ID}}
    lines = [json.dumps(tool_use), json.dumps(progress)]
    (cc_dir / f'{SESSION_ID}.jsonl').write_text('\n'.join(lines) + '\n')


def run_list_agents(fake_home: Path, project: Path) -> subprocess.CompletedProcess:
    env = {**os.environ, 'HOME': str(fake_home)}
    cmd = [sys.executable, '-m', 'src.pipeline.list_agents', '--project', str(project)]
    return subprocess.run(cmd, cwd=REPO_ROOT, env=env, capture_output=True, text=True)


def assert_output(result: subprocess.CompletedProcess) -> None:
    assert result.returncode == 0, result.stderr
    assert AGENT_ID in result.stdout, result.stdout
    assert AGENT_TYPE in result.stdout, result.stdout


if __name__ == "__main__":
    test_workflow()
    print("PASS")

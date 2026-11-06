# render_runner_flags report

spawn:      CLAUDE_CODE_FORK_SUBAGENT=0 /fake/claude --model 'claude-sonnet-5' --permission-mode bypassPermissions --disallowedTools Agent
spawn_file: CLAUDE_CODE_FORK_SUBAGENT=0 /fake/claude --model 'claude-sonnet-5' --permission-mode bypassPermissions --disallowedTools Agent
revive:     CLAUDE_CODE_FORK_SUBAGENT=0 /fake/claude --model 'claude-sonnet-5' --permission-mode bypassPermissions --disallowedTools Agent --resume '11111111-2222-3333-4444-555555555555'

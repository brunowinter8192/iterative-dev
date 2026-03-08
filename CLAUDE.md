# iterative-dev Plugin — Project Rules

## Worker Spawning

- **Terminal:** Ghostty
- Worker-Spawns open a Ghostty window automatically via `open -na Ghostty.app` with isolation flags
- Ghostty 1.3+: Uses native AppleScript API instead
- tmux session name: `workers`

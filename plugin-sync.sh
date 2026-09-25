#!/bin/bash

# INFRASTRUCTURE

set -euo pipefail

MARKETPLACE="brunowinter-plugins"
CACHE_BASE="$HOME/.claude/plugins/cache/$MARKETPLACE"
INSTALLED_JSON="$HOME/.claude/plugins/installed_plugins.json"

# ORCHESTRATOR

main() {
    require_args "$@"
    resolve_repo "$@"
    require_plugin_json
    read_installed_version
    read_source_version
    warn_on_version_drift
    resolve_cache_dir
    print_sync_header
    sync_cache
    update_installed_metadata
    print_done
}

# FUNCTIONS

require_args() {
    if [ $# -ne 2 ]; then
        echo "Usage: plugin-sync.sh <plugin-name> <local-repo-path>"
        echo "Example: plugin-sync.sh rag ~/Documents/ai/Meta/ClaudeCode/cli/rag-cli"
        exit 1
    fi
}

resolve_repo() {
    PLUGIN_NAME="$1"
    REPO_PATH="$(cd "$2" && pwd)"

    if [ ! -d "$REPO_PATH" ]; then
        echo "ERROR: Repo path does not exist: $2"
        exit 1
    fi
}

require_plugin_json() {
    PLUGIN_JSON="$REPO_PATH/.claude-plugin/plugin.json"
    if [ ! -f "$PLUGIN_JSON" ]; then
        echo "ERROR: No .claude-plugin/plugin.json found in $REPO_PATH"
        exit 1
    fi
}

read_installed_version() {
    INSTALLED_VERSION=$(python3 -c "
import json
data = json.load(open('$INSTALLED_JSON'))
key = '${PLUGIN_NAME}@${MARKETPLACE}'
entries = data.get('plugins', {}).get(key, [])
if entries:
    print(entries[0].get('version', ''))
")

    if [ -z "$INSTALLED_VERSION" ]; then
        echo "ERROR: Plugin '$PLUGIN_NAME' not found in installed_plugins.json. Run /plugin install first."
        exit 1
    fi
}

read_source_version() {
    SOURCE_VERSION=$(python3 -c "import json; print(json.load(open('$PLUGIN_JSON'))['version'])")
}

warn_on_version_drift() {
    if [ "$SOURCE_VERSION" != "$INSTALLED_VERSION" ]; then
        echo "WARNING: VERSION DRIFT DETECTED"
        echo "   Source plugin.json says: $SOURCE_VERSION"
        echo "   Installed (cache):       $INSTALLED_VERSION"
        echo "   → Syncing to INSTALLED version $INSTALLED_VERSION"
        echo "   To upgrade installed version, run: /plugin install $PLUGIN_NAME"
        echo ""
    fi
}

resolve_cache_dir() {
    VERSION="$INSTALLED_VERSION"
    CACHE_DIR="$CACHE_BASE/$PLUGIN_NAME/$VERSION"

    if [ ! -d "$CACHE_DIR" ]; then
        echo "ERROR: Cache directory does not exist: $CACHE_DIR"
        echo "Plugin '$PLUGIN_NAME' v$VERSION installed in registry but cache missing. Run /plugin install."
        exit 1
    fi
}

print_sync_header() {
    echo "Syncing $PLUGIN_NAME v$VERSION..."
    echo "  From: $REPO_PATH"
    echo "  To:   $CACHE_DIR"
}

sync_cache() {
    rsync -av \
        --filter='P venv/' --filter='P .venv/' --filter='P node_modules/' --filter='P .env' \
        --filter=':- .gitignore' \
        --exclude='.git' \
        --delete \
        "$REPO_PATH/" "$CACHE_DIR/"
}

update_installed_metadata() {
    local sha timestamp
    sha=$(cd "$REPO_PATH" && git rev-parse HEAD)
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    python3 -c "
import json

with open('$INSTALLED_JSON') as f:
    data = json.load(f)

key = '${PLUGIN_NAME}@${MARKETPLACE}'
if key not in data.get('plugins', {}):
    print(f'WARNING: {key} not found in installed_plugins.json')
else:
    for entry in data['plugins'][key]:
        entry['gitCommitSha'] = '$sha'
        entry['lastUpdated'] = '$timestamp'

    with open('$INSTALLED_JSON', 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')

    print(f'Updated metadata: SHA={\"$sha\"[:8]}, timestamp=$timestamp')
"
}

print_done() {
    echo ""
    echo "Done. Start a new Claude Code session to pick up changes."
}

main "$@"

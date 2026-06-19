#!/bin/bash
# Sync local plugin repo to Claude Code plugin cache.
# Bypasses /plugin install — direct, reliable, no version-check issues.
#
# Usage: plugin-sync.sh <plugin-name> <local-repo-path>
# Example: plugin-sync.sh rag ~/Documents/ai/Meta/ClaudeCode/cli/rag-cli

set -euo pipefail

MARKETPLACE="brunowinter-plugins"
CACHE_BASE="$HOME/.claude/plugins/cache/$MARKETPLACE"
INSTALLED_JSON="$HOME/.claude/plugins/installed_plugins.json"

# --- Validate args ---

if [ $# -ne 2 ]; then
    echo "Usage: plugin-sync.sh <plugin-name> <local-repo-path>"
    echo "Example: plugin-sync.sh rag ~/Documents/ai/Meta/ClaudeCode/cli/rag-cli"
    exit 1
fi

PLUGIN_NAME="$1"
REPO_PATH="$(cd "$2" && pwd)"

if [ ! -d "$REPO_PATH" ]; then
    echo "ERROR: Repo path does not exist: $2"
    exit 1
fi

PLUGIN_JSON="$REPO_PATH/.claude-plugin/plugin.json"
if [ ! -f "$PLUGIN_JSON" ]; then
    echo "ERROR: No .claude-plugin/plugin.json found in $REPO_PATH"
    exit 1
fi

# --- Resolve version: installed first, source as reference ---

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

SOURCE_VERSION=$(python3 -c "import json; print(json.load(open('$PLUGIN_JSON'))['version'])")

if [ "$SOURCE_VERSION" != "$INSTALLED_VERSION" ]; then
    echo "⚠️  VERSION DRIFT DETECTED"
    echo "   Source plugin.json says: $SOURCE_VERSION"
    echo "   Installed (cache):       $INSTALLED_VERSION"
    echo "   → Syncing to INSTALLED version $INSTALLED_VERSION"
    echo "   To upgrade installed version, run: /plugin install $PLUGIN_NAME"
    echo ""
fi

VERSION="$INSTALLED_VERSION"
CACHE_DIR="$CACHE_BASE/$PLUGIN_NAME/$VERSION"

if [ ! -d "$CACHE_DIR" ]; then
    echo "ERROR: Cache directory does not exist: $CACHE_DIR"
    echo "Plugin '$PLUGIN_NAME' v$VERSION installed in registry but cache missing. Run /plugin install."
    exit 1
fi

# --- Sync files ---

echo "Syncing $PLUGIN_NAME v$VERSION..."
echo "  From: $REPO_PATH"
echo "  To:   $CACHE_DIR"

# Use .gitignore to exclude untracked files from transfer.
# Protect runtime artifacts (installed by /plugin install) from --delete.
rsync -av \
    --filter='P venv/' --filter='P .venv/' --filter='P node_modules/' --filter='P .env' \
    --filter=':- .gitignore' \
    --exclude='.git' \
    --delete \
    "$REPO_PATH/" "$CACHE_DIR/"

# --- Update installed_plugins.json ---

SHA=$(cd "$REPO_PATH" && git rev-parse HEAD)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

python3 -c "
import json

with open('$INSTALLED_JSON') as f:
    data = json.load(f)

key = '${PLUGIN_NAME}@${MARKETPLACE}'
if key not in data.get('plugins', {}):
    print(f'WARNING: {key} not found in installed_plugins.json')
else:
    for entry in data['plugins'][key]:
        entry['gitCommitSha'] = '$SHA'
        entry['lastUpdated'] = '$TIMESTAMP'

    with open('$INSTALLED_JSON', 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')

    print(f'Updated metadata: SHA={\"$SHA\"[:8]}, timestamp=$TIMESTAMP')
"

echo ""
echo "Done. Start a new Claude Code session to pick up changes."

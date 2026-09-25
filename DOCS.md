# ./

## Role

Repository root of the iterative-dev plugin. Holds the legacy cache-sync script; commands live in `bin/`, implementations in `src/`, skills in `skills/`. Touch only for repo-wide plumbing. Do not add commands or logic here.

## Public Interface

No `__init__.py`. `plugin-sync.sh` is run by hand with a plugin name and a repo path.

## Flow

Plugin name and local repo path in → installed version resolved from the registry → repo rsynced into that version's cache directory → registry SHA and timestamp updated → done message out.

## Modules

### plugin-sync.sh (144 LOC)

**Purpose:** Sync a local plugin repo into the plugin cache under the installed version, warning on version drift.
**Reads:** local repo, `.claude-plugin/plugin.json`, `installed_plugins.json`.
**Writes:** plugin cache directory, `installed_plugins.json` (SHA and timestamp).
**Called by:** nothing. DEAD CODE candidate: no file in the repo and no symlink in `~/.local/bin` references it; `bin/plugin-publish` covers the same sync plus push and version bump.
**Calls out:** rsync, python3, git.

## State

None.

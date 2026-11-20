#!/bin/sh
# Starts Claude Code with the configuration of this repository only: the skills in .claude/skills/,
# the settings in .claude/ and CLAUDE.md. Plugins, skills, hooks and settings from ~/.claude are not loaded.
#   scripts/claude.sh [arguments for claude]
set -eu
cd "$(dirname "$0")/.."
exec claude --setting-sources project,local "$@"

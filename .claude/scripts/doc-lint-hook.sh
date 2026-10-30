#!/usr/bin/env bash
# Reads a PostToolUse payload on stdin and returns doc-lint.sh findings for the edited file as additionalContext.
set -u

# SILENT: unparsable hook input means there is nothing to lint, and a hook error would interrupt the edit.
file="$(jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
[ -n "$file" ] || exit 0

output="$("$(dirname "${BASH_SOURCE[0]}")/doc-lint.sh" "$file")"
[ -n "$output" ] || exit 0

jq -n --arg context "$output" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context}}'

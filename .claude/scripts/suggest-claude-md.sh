#!/bin/zsh
# Suggests CLAUDE.md additions based on the current session transcript.
# Triggered by SessionEnd and PreCompact hooks.

# Prevent infinite loop when this script itself calls claude
[[ -n "$SUGGEST_CLAUDE_MD_RUNNING" ]] && exit 0

input=$(cat)

# Try transcript_path from hook input first
transcript=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

# Fall back: derive from session_id + cwd
if [[ -z "$transcript" || ! -f "$transcript" ]]; then
  session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
  cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
  if [[ -n "$session_id" && -n "$cwd" ]]; then
    project_dir=$(echo "$cwd" | tr '/.' '-')
    transcript="$HOME/.claude/projects/${project_dir}/${session_id}.jsonl"
  fi
fi

[[ -z "$transcript" || ! -f "$transcript" ]] && exit 0

# Extract user messages (excluding meta entries)
conversation=$(jq -r '
  select(.type == "user" and (.isMeta != true)) |
  .message.content |
  if type == "string" then .
  elif type == "array" then (map(select(.type == "text") | .text) | join(" "))
  else empty
  end
' "$transcript" 2>/dev/null | grep -v '^$' | tail -c 8000)

[[ -z "$conversation" ]] && exit 0

claude_md="$(cat "$DOTFILES/.claude/CLAUDE.md")"

prompt="You are reviewing a Claude Code session. Suggest rules to add to CLAUDE.md based on patterns observed.

Current CLAUDE.md:
${claude_md}

Recent user messages from this session:
${conversation}

Suggest 0-3 specific, actionable rules NOT already covered by the existing CLAUDE.md. Focus on behavioral patterns, preferences, or constraints that emerged from this session.

Format:
[CATEGORY] Rule text

Output ONLY the suggestions. If nothing notable emerged, output nothing."

suggestions=$(SUGGEST_CLAUDE_MD_RUNNING=1 /opt/homebrew/bin/claude --print "$prompt" 2>/dev/null)

[[ -z "$suggestions" ]] && exit 0

echo ""
echo "💡 CLAUDE.md への追記候補（このセッションより）:"
echo "$suggestions"
echo ""

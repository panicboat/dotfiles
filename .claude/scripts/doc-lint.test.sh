#!/usr/bin/env bash
# Behavior tests for doc-lint.sh; they need vale and textlint (see .config) except test_succeeds_without_tools.
set -u

# Hooks export GIT_DIR and GIT_INDEX_FILE; clear them so the helpers never target the outer repository.
unset $(git rev-parse --local-env-vars)

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
real_home="$HOME"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

case_failed=0
lint_out=""
lint_err=""
lint_status=0
editor_out=""
editor_err=""
editor_status=0
commit_out=""
commit_status=0

# Prints the path of a temporary HOME that links the dotfiles config, scripts, and tool directory.
make_home() {
  local with_tools=1 with_scripts=1 home
  while [ $# -gt 0 ]; do
    case "$1" in
      --without-tools) with_tools=0 ;;
      --without-scripts) with_scripts=0 ;;
    esac
    shift
  done
  home="$(mktemp -d "$work/home.XXXXXX")"
  mkdir -p "$home/.config/vale" "$home/.config/textlint" "$home/.claude" "$home/.local/share"
  ln -s "$repo_root/.config/vale/.vale.ini" "$home/.config/vale/.vale.ini"
  ln -s "$repo_root/.config/textlint/.textlintrc.json" "$home/.config/textlint/.textlintrc.json"
  if [ "$with_scripts" = 1 ]; then
    ln -s "$repo_root/.claude/scripts" "$home/.claude/scripts"
  fi
  if [ "$with_tools" = 1 ]; then
    ln -s "$real_home/.local/share/doc-lint" "$home/.local/share/doc-lint"
  fi
  printf '%s\n' "$home"
}

assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  printf '    expected to contain: %s\n    actual: %s\n' "$2" "$1" >&2
  case_failed=1
}

assert_not_contains() {
  case "$1" in
    *"$2"*)
      printf '    expected not to contain: %s\n    actual: %s\n' "$2" "$1" >&2
      case_failed=1
      ;;
  esac
}

assert_equals() {
  if [ "$1" != "$2" ]; then
    printf '    expected: %s\n    actual: %s\n' "$2" "$1" >&2
    case_failed=1
  fi
}

# Fails the case when vale or textlint is missing, so a missing tool never passes as a skip.
require_tools() {
  if ! command -v vale >/dev/null 2>&1; then
    printf '    vale is not installed\n' >&2
    case_failed=1
  fi
  if [ ! -x "$real_home/.local/share/doc-lint/node_modules/.bin/textlint" ] || ! command -v node >/dev/null 2>&1; then
    printf '    textlint or node is not installed\n' >&2
    case_failed=1
  fi
}

# Runs doc-lint.sh from <dir> and sets lint_out, lint_err, and lint_status.
run_lint() {
  local home="$1" dir="$2" err_file
  shift 2
  err_file="$(mktemp "$work/err.XXXXXX")"
  lint_out="$(cd "$dir" && HOME="$home" "$home/.claude/scripts/doc-lint.sh" "$@" 2>"$err_file")"
  lint_status=$?
  lint_err="$(cat "$err_file")"
}

# Runs git in <dir> without global config, hooks, or identity.
git_in() {
  local home="$1" dir="$2"
  shift 2
  HOME="$home" git -C "$dir" -c core.hooksPath=/dev/null -c user.name=test -c user.email=test@example.com "$@"
}

# Runs doc-lint-hook.sh from <dir> with the PostToolUse input <json> and sets editor_out, editor_err, and editor_status.
run_editor_hook() {
  local home="$1" dir="$2" json="$3" err_file
  err_file="$(mktemp "$work/err.XXXXXX")"
  editor_out="$(cd "$dir" && printf '%s' "$json" | HOME="$home" "$home/.claude/scripts/doc-lint-hook.sh" 2>"$err_file")"
  editor_status=$?
  editor_err="$(cat "$err_file")"
}

# Prints the PostToolUse input for an edit of <file>.
edit_input() {
  jq -n --arg path "$1" '{tool_input: {file_path: $path}}'
}

# Commits in <dir> through the dotfiles git hooks and sets commit_out (stdout and stderr) and commit_status.
commit_with_hooks() {
  local home="$1" dir="$2"
  commit_out="$(HOME="$home" git -C "$dir" -c core.hooksPath="$repo_root/.githooks" -c user.name=test -c user.email=test@example.com commit -q -m test 2>&1)"
  commit_status=$?
}

commit_count() {
  git_in "$1" "$2" rev-list --count HEAD 2>/dev/null
}

# Creates a repository in <dir> whose only commit holds docs/a.md with a passive line.
make_repository_with_old_passive_line() {
  local home="$1" dir="$2"
  mkdir -p "$dir/docs"
  git_in "$home" "$dir" init -q
  printf 'The old file is deleted.\n' >"$dir/docs/a.md"
  git_in "$home" "$dir" add docs/a.md
  git_in "$home" "$dir" commit -q -m initial
}

# Commits a new passive line in docs/a.md of <dir> and asserts that the hook reports only that line.
assert_commit_reports_only_new_line() {
  local home="$1" dir="$2"
  printf '\nThe Pod is read by a panel.\n' >>"$dir/docs/a.md"
  git_in "$home" "$dir" add docs/a.md
  commit_with_hooks "$home" "$dir"
  assert_equals "$commit_status" "0"
  assert_contains "$commit_out" "docs/a.md:3:"
  assert_contains "$commit_out" "is read"
  assert_not_contains "$commit_out" "is deleted"
  assert_equals "$(commit_count "$home" "$dir")" "2"
}

write_original_lines() {
  cat >"$1" <<'EOF'
The Pod is read through a new `WatchWorkflowPod` API (`GET /api/v1/stream/workflows/{namespace}/{name}/pods/{podName}`), which needs permission to read the Workflow and to watch Pods in its namespace.

The button is not shown for workflows that exist only in the archive database, and a Pod that has already been deleted cannot be displayed.
EOF
}

write_reviewed_lines() {
  cat >"$1" <<'EOF'
The panel reads the Pod through a new `WatchWorkflowPod` API (`GET /api/v1/stream/workflows/{namespace}/{name}/pods/{podName}`), which needs permission to read the Workflow and to watch Pods in its namespace.

The button doesn't appear for workflows that exist only in the archive database, and you can't view a Pod that has already been deleted.
EOF
}

test_flags_passive_voice_in_original_lines() {
  local home dir
  home="$(make_home)"
  dir="$work/original"
  mkdir -p "$dir"
  write_original_lines "$dir/a.md"
  run_lint "$home" "$dir" a.md
  assert_contains "$lint_out" "is read"
  assert_contains "$lint_out" "been deleted"
  assert_contains "$lint_out" "be displayed"
}

test_accepts_reviewed_lines() {
  local home dir
  home="$(make_home)"
  dir="$work/reviewed"
  mkdir -p "$dir"
  write_reviewed_lines "$dir/a.md"
  run_lint "$home" "$dir" a.md
  assert_contains "$lint_out" "been deleted"
  assert_not_contains "$lint_out" "is read"
  assert_not_contains "$lint_out" "be displayed"
}

test_routes_japanese_to_textlint() {
  local home dir
  home="$(make_home)"
  dir="$work/japanese"
  mkdir -p "$dir"
  printf '私はこのドキュメントを書きました!!\n' >"$dir/a.md"
  run_lint "$home" "$dir" a.md
  assert_contains "$lint_out" "no-exclamation-question-mark"
  assert_not_contains "$lint_out" "Google."
}

test_uses_repository_vale_config() {
  local home dir
  home="$(make_home)"
  dir="$work/repo-vale"
  mkdir -p "$dir/styles/X"
  git_in "$home" "$dir" init -q
  cat >"$dir/.vale.ini" <<'EOF'
StylesPath = styles
MinAlertLevel = suggestion

[*.md]
BasedOnStyles = X
EOF
  cat >"$dir/styles/X/Foo.yml" <<'EOF'
extends: existence
message: "Avoid '%s'."
level: warning
tokens:
  - foo
EOF
  printf 'The foo is deleted by the tool.\n' >"$dir/a.md"
  run_lint "$home" "$work" "$dir/a.md"
  assert_contains "$lint_out" "X.Foo"
  assert_not_contains "$lint_out" "Google."
}

test_reports_only_changed_lines() {
  local home dir
  home="$(make_home)"
  dir="$work/changed"
  mkdir -p "$dir"
  git_in "$home" "$dir" init -q
  printf 'The old file is deleted.\n' >"$dir/a.md"
  git_in "$home" "$dir" add a.md
  git_in "$home" "$dir" commit -q -m initial
  printf '\nThe new file is deleted.\n' >>"$dir/a.md"
  run_lint "$home" "$work" "$dir/a.md"
  assert_contains "$lint_out" "a.md:3:"
  assert_not_contains "$lint_out" "a.md:1:"
}

test_reports_all_lines_without_head() {
  local home dir
  home="$(make_home)"
  dir="$work/no-head"
  mkdir -p "$dir"
  git_in "$home" "$dir" init -q
  printf 'The file is deleted.\n' >"$dir/a.md"
  run_lint "$home" "$dir" a.md
  assert_contains "$lint_out" "Google.Passive"
}

test_handles_path_with_spaces() {
  local home dir
  home="$(make_home)"
  dir="$work/my docs"
  mkdir -p "$dir"
  git_in "$home" "$dir" init -q
  printf 'A clean line.\n' >"$dir/a b.md"
  git_in "$home" "$dir" add "a b.md"
  git_in "$home" "$dir" commit -q -m initial
  printf '\nThe file is deleted.\n' >>"$dir/a b.md"
  run_lint "$home" "$dir" "a b.md"
  assert_contains "$lint_out" "a b.md:3:"
  assert_contains "$lint_out" "Google.Passive"
}

test_skips_vendored_paths() {
  local home dir
  home="$(make_home)"
  dir="$work/vendored"
  mkdir -p "$dir/node_modules/x" "$dir/vendor" "$dir/.superpowers"
  printf 'The file is deleted.\n' | tee "$dir/node_modules/x/a.md" "$dir/vendor/a.md" "$dir/.superpowers/a.md" >"$dir/control.md"
  run_lint "$home" "$dir" control.md
  assert_contains "$lint_out" "Google.Passive"
  run_lint "$home" "$dir" node_modules/x/a.md vendor/a.md .superpowers/a.md
  assert_equals "$lint_out" ""
  assert_equals "$lint_status" "0"
}

test_ignores_non_markdown_and_missing_files() {
  local home dir
  home="$(make_home)"
  dir="$work/ignored"
  mkdir -p "$dir"
  printf 'The file is deleted.\n' | tee "$dir/a.txt" >"$dir/control.md"
  printf '私はこのドキュメントを書きました!!\n' >"$dir/ja.txt"
  run_lint "$home" "$dir" control.md
  assert_contains "$lint_out" "Google.Passive"
  run_lint "$home" "$dir" a.txt ja.txt gone.md
  assert_equals "$lint_out" ""
  assert_equals "$lint_status" "0"
}

test_caps_findings_per_file() {
  local home dir i count
  home="$(make_home)"
  dir="$work/capped"
  mkdir -p "$dir"
  : >"$dir/a.md"
  for i in $(seq 1 40); do
    printf 'Item %s is deleted.\n\n' "$i" >>"$dir/a.md"
  done
  run_lint "$home" "$dir" a.md
  count="$(printf '%s\n' "$lint_out" | grep -c 'Google.Passive')"
  assert_equals "$count" "30"
  assert_contains "$lint_out" "10 more"
}

test_appends_guide_url_only_with_findings() {
  local home dir count
  home="$(make_home)"
  dir="$work/guide"
  mkdir -p "$dir"
  printf 'The panel reads the Pod.\n' >"$dir/clean.md"
  printf 'The file is deleted.\n' >"$dir/dirty.md"
  run_lint "$home" "$dir" dirty.md
  assert_contains "$lint_out" "style-guide"
  run_lint "$home" "$dir" clean.md
  assert_equals "$lint_out" ""
  run_lint "$home" "$dir" clean.md dirty.md
  count="$(printf '%s\n' "$lint_out" | grep -c 'style-guide')"
  assert_equals "$count" "1"
}

test_succeeds_without_tools() {
  local home dir
  home="$(make_home --without-tools)"
  dir="$work/no-tools"
  mkdir -p "$dir"
  printf 'The file is deleted.\n' >"$dir/en.md"
  printf '私はこのドキュメントを書きました!!\n' >"$dir/ja.md"
  PATH=/usr/bin:/bin run_lint "$home" "$dir" en.md ja.md
  assert_equals "$lint_status" "0"
  assert_equals "$lint_out" ""
  assert_contains "$lint_err" "doc-lint: vale not found"
  assert_contains "$lint_err" "doc-lint: textlint not found"
}

test_survives_broken_repository_textlint_config() {
  local home dir
  home="$(make_home)"
  dir="$work/broken-textlint"
  mkdir -p "$dir"
  git_in "$home" "$dir" init -q
  printf '{"rules": {"preset-ja-technical-writing": true}}\n' >"$dir/.textlintrc.json"
  printf '私はこのドキュメントを書きました!!\n' >"$dir/a.md"
  run_lint "$home" "$dir" a.md
  assert_equals "$lint_status" "0"
}

test_hook_returns_additional_context() {
  local home dir context
  home="$(make_home)"
  dir="$work/hook-context"
  mkdir -p "$dir"
  printf 'The Pod is read by a panel.\n' >"$dir/a.md"
  run_editor_hook "$home" "$dir" "$(edit_input "$dir/a.md")"
  assert_equals "$editor_status" "0"
  if ! printf '%s' "$editor_out" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null 2>&1; then
    printf '    expected a PostToolUse hookSpecificOutput\n    actual: %s\n' "$editor_out" >&2
    case_failed=1
  fi
  context="$(printf '%s' "$editor_out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
  assert_contains "$context" "is read"
}

test_hook_is_silent_for_other_files() {
  local home dir
  home="$(make_home)"
  dir="$work/hook-other"
  mkdir -p "$dir"
  printf 'The Pod is read by a panel.\n' >"$dir/a.txt"
  run_editor_hook "$home" "$dir" "$(edit_input "$dir/a.txt")"
  assert_equals "$editor_out" ""
  assert_equals "$editor_err" ""
  assert_equals "$editor_status" "0"
}

test_hook_uses_file_repository_not_cwd() {
  local home dir context
  home="$(make_home)"
  dir="$work/hook-repo"
  mkdir -p "$dir/styles/X"
  git_in "$home" "$dir" init -q
  cat >"$dir/.vale.ini" <<'EOF'
StylesPath = styles
MinAlertLevel = suggestion

[*.md]
BasedOnStyles = X
EOF
  cat >"$dir/styles/X/Foo.yml" <<'EOF'
extends: existence
message: "Avoid '%s'."
level: warning
tokens:
  - foo
EOF
  printf 'The foo is deleted by the tool.\n' >"$dir/a.md"
  run_editor_hook "$home" "$work" "$(edit_input "$dir/a.md")"
  context="$(printf '%s' "$editor_out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
  assert_contains "$context" "X.Foo"
  assert_not_contains "$context" "Google."
}

test_pre_commit_reports_and_succeeds() {
  local home dir
  home="$(make_home)"
  dir="$work/commit-report"
  make_repository_with_old_passive_line "$home" "$dir"
  assert_commit_reports_only_new_line "$home" "$dir"
}

test_pre_commit_reports_changed_lines_in_linked_worktree() {
  local home main dir
  home="$(make_home)"
  main="$work/commit-linked-main"
  dir="$work/commit-linked"
  make_repository_with_old_passive_line "$home" "$main"
  git_in "$home" "$main" worktree add -q -b feature "$dir"
  assert_commit_reports_only_new_line "$home" "$dir"
}

test_pre_commit_handles_paths_with_spaces() {
  local home dir
  home="$(make_home)"
  dir="$work/commit-spaces"
  mkdir -p "$dir/my docs"
  git_in "$home" "$dir" init -q
  printf 'placeholder\n' >"$dir/notes.txt"
  git_in "$home" "$dir" add notes.txt
  git_in "$home" "$dir" commit -q -m initial
  printf 'The file is deleted.\n' >"$dir/my docs/a b.md"
  git_in "$home" "$dir" add "my docs/a b.md"
  commit_with_hooks "$home" "$dir"
  assert_equals "$commit_status" "0"
  assert_contains "$commit_out" "my docs/a b.md:1:"
  assert_contains "$commit_out" "Google.Passive"
  assert_equals "$(commit_count "$home" "$dir")" "2"
}

test_pre_commit_handles_deleted_markdown() {
  local home dir
  home="$(make_home)"
  dir="$work/commit-deleted"
  mkdir -p "$dir"
  git_in "$home" "$dir" init -q
  printf 'The file is deleted.\n' >"$dir/a.md"
  git_in "$home" "$dir" add a.md
  git_in "$home" "$dir" commit -q -m initial
  git_in "$home" "$dir" rm -q a.md
  commit_with_hooks "$home" "$dir"
  assert_equals "$commit_status" "0"
  assert_equals "$commit_out" ""
  assert_equals "$(commit_count "$home" "$dir")" "2"
}

test_pre_commit_without_doc_lint_succeeds() {
  local home dir
  home="$(make_home --without-scripts)"
  dir="$work/commit-no-script"
  mkdir -p "$dir"
  git_in "$home" "$dir" init -q
  printf 'The file is deleted.\n' >"$dir/a.md"
  git_in "$home" "$dir" add a.md
  commit_with_hooks "$home" "$dir"
  assert_equals "$commit_status" "0"
  assert_equals "$commit_out" ""
  assert_equals "$(commit_count "$home" "$dir")" "1"
}

test_pre_commit_chains_native_hook() {
  local home dir marker
  home="$(make_home)"
  dir="$work/commit-native"
  marker="$work/native-hook-ran"
  mkdir -p "$dir"
  git_in "$home" "$dir" init -q
  printf '#!/bin/sh\ntouch "%s"\n' "$marker" >"$dir/.git/hooks/pre-commit"
  chmod +x "$dir/.git/hooks/pre-commit"
  printf 'The file is deleted.\n' >"$dir/a.md"
  git_in "$home" "$dir" add a.md
  commit_with_hooks "$home" "$dir"
  assert_equals "$commit_status" "0"
  assert_contains "$commit_out" "Google.Passive"
  if [ ! -e "$marker" ]; then
    printf '    expected the repository pre-commit hook to run\n' >&2
    case_failed=1
  fi
}

test_commit_msg_does_not_lint() {
  local home dir out
  home="$(make_home)"
  dir="$work/commit-msg"
  mkdir -p "$dir"
  git_in "$home" "$dir" init -q
  printf 'The file is deleted.\n' >"$dir/a.md"
  git_in "$home" "$dir" add a.md
  printf 'docs: add a\n' >"$work/commit-msg.txt"
  out="$(cd "$dir" && HOME="$home" "$repo_root/.githooks/pre-commit" 2>&1)"
  assert_contains "$out" "Google.Passive"
  out="$(cd "$dir" && HOME="$home" "$repo_root/.githooks/commit-msg" "$work/commit-msg.txt" 2>&1)"
  assert_equals "$?" "0"
  assert_not_contains "$out" "Google."
}

test_git_hooks_stay_identical() {
  if ! cmp -s "$repo_root/.githooks/pre-commit" "$repo_root/.githooks/commit-msg"; then
    printf '    .githooks/pre-commit and .githooks/commit-msg differ\n' >&2
    case_failed=1
  fi
}

tests="
test_flags_passive_voice_in_original_lines
test_accepts_reviewed_lines
test_routes_japanese_to_textlint
test_uses_repository_vale_config
test_reports_only_changed_lines
test_reports_all_lines_without_head
test_handles_path_with_spaces
test_skips_vendored_paths
test_ignores_non_markdown_and_missing_files
test_caps_findings_per_file
test_appends_guide_url_only_with_findings
test_succeeds_without_tools
test_survives_broken_repository_textlint_config
test_hook_returns_additional_context
test_hook_is_silent_for_other_files
test_hook_uses_file_repository_not_cwd
test_pre_commit_reports_and_succeeds
test_pre_commit_reports_changed_lines_in_linked_worktree
test_pre_commit_handles_paths_with_spaces
test_pre_commit_handles_deleted_markdown
test_pre_commit_without_doc_lint_succeeds
test_pre_commit_chains_native_hook
test_commit_msg_does_not_lint
test_git_hooks_stay_identical
"

failures=0
for name in $tests; do
  case_failed=0
  if [ "$name" != test_succeeds_without_tools ]; then
    require_tools
  fi
  "$name"
  if [ "$case_failed" = 0 ]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s\n' "$name"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  printf '%s test(s) failed\n' "$failures" >&2
  exit 1
fi

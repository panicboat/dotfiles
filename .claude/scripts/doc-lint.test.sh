#!/usr/bin/env bash
# Behavior tests for doc-lint.sh; they need vale and textlint (see .config) except test_succeeds_without_tools.
set -u

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
real_home="$HOME"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

case_failed=0
lint_out=""
lint_err=""
lint_status=0

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

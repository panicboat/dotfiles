#!/usr/bin/env bash
# Prints style findings for Markdown files (Vale for English, textlint for Japanese) and always exits 0.
set -u

guide_url="https://kubernetes.io/docs/contribute/style/style-guide/"
max_findings=30
tools_dir="$HOME/.local/share/doc-lint"
textlint_bin="$tools_dir/node_modules/.bin/textlint"

vale_warned=0
textlint_warned=0
found=0

first_config() {
  local dir="$1" name
  shift
  for name in "$@"; do
    if [ -f "$dir/$name" ]; then
      printf '%s\n' "$dir/$name"
      return 0
    fi
  done
  return 1
}

# Runs in the caller's shell (not a command substitution) so the warning flag survives across files.
vale_available() {
  command -v vale >/dev/null 2>&1 && return 0
  if [ "$vale_warned" = 0 ]; then
    echo "doc-lint: vale not found" >&2
    vale_warned=1
  fi
  return 1
}

textlint_available() {
  [ -x "$textlint_bin" ] && command -v node >/dev/null 2>&1 && return 0
  if [ "$textlint_warned" = 0 ]; then
    echo "doc-lint: textlint not found" >&2
    textlint_warned=1
  fi
  return 1
}

run_vale() {
  local file="$1" top="$2" config
  # SILENT: vale exit codes and stderr are discarded so a lint failure never blocks the editor or the commit.
  if [ -n "$top" ] && config="$(first_config "$top" .vale.ini _vale.ini vale.ini .vale _vale .config/vale.ini)"; then
    vale --config "$config" --output=line "$file" 2>/dev/null || true
  else
    VALE_STYLES_PATH="$tools_dir/vale-styles" vale --config "$HOME/.config/vale/.vale.ini" --output=line "$file" 2>/dev/null || true
  fi
}

run_textlint() {
  local file="$1" top="$2" config
  # SILENT: textlint exits 1 on findings and on a repository config without installed rules, and neither may block the caller.
  if [ -n "$top" ] && config="$(first_config "$top" .textlintrc .textlintrc.json .textlintrc.yml .textlintrc.yaml .textlintrc.js)"; then
    "$textlint_bin" --config "$config" --rules-base-directory "$top/node_modules" --format unix "$file" 2>/dev/null || true
  else
    "$textlint_bin" --config "$HOME/.config/textlint/.textlintrc.json" --rules-base-directory "$tools_dir/node_modules" --format unix "$file" 2>/dev/null || true
  fi
}

# Prints "all", or the changed line ranges ("3-5 9-9") of a tracked file, or nothing when no line changed.
changed_ranges() {
  local dir="$1" base="$2"
  if ! git -C "$dir" rev-parse --verify -q HEAD >/dev/null 2>&1 \
    || ! git -C "$dir" ls-files --error-unmatch -- "$base" >/dev/null 2>&1; then
    echo all
    return 0
  fi
  git -C "$dir" diff --no-color --no-ext-diff --no-textconv -U0 HEAD -- "$base" 2>/dev/null | awk '
    /^@@/ {
      split($3, plus, ",")
      start = substr(plus[1], 2) + 0
      count = (plus[2] == "") ? 1 : plus[2] + 0
      if (count > 0) printf "%s%d-%d", (n++ ? " " : ""), start, start + count - 1
    }
    END { if (n) print "" }
  '
}

filter_findings() {
  ABS_PREFIX="$1:" RANGES="$2" awk '
    BEGIN { n = split(ENVIRON["RANGES"], range, " "); prefix = ENVIRON["ABS_PREFIX"] }
    index($0, prefix) != 1 { next }
    {
      rest = substr($0, length(prefix) + 1)
      if (rest !~ /^[0-9]+:/) next
      line = rest + 0
      if (ENVIRON["RANGES"] == "all") { print; next }
      for (i = 1; i <= n; i++) {
        split(range[i], bound, "-")
        if (line >= bound[1] + 0 && line <= bound[2] + 0) { print; next }
      }
    }
  '
}

lint_file() {
  local file="$1" dir base abs top ranges raw findings total
  case "$file" in
    *.md) ;;
    *) return 0 ;;
  esac
  [ -f "$file" ] || return 0
  dir="$(cd "$(dirname "$file")" && pwd -P)" || return 0
  base="$(basename "$file")"
  abs="$dir/$base"
  case "$abs" in
    */node_modules/* | */vendor/* | */.superpowers/*) return 0 ;;
  esac

  ranges="$(changed_ranges "$dir" "$base")"
  [ -n "$ranges" ] || return 0
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"

  if LC_ALL=en_US.UTF-8 grep -q '[ぁ-んァ-ヶ]' "$file"; then
    textlint_available || return 0
    raw="$(run_textlint "$abs" "$top")"
  else
    vale_available || return 0
    raw="$(run_vale "$abs" "$top")"
  fi

  findings="$(printf '%s\n' "$raw" | filter_findings "$abs" "$ranges")"
  [ -n "$findings" ] || return 0

  total="$(printf '%s\n' "$findings" | awk 'END { print NR }')"
  printf '%s\n' "$findings" | awk -v max="$max_findings" 'NR <= max'
  if [ "$total" -gt "$max_findings" ]; then
    echo "doc-lint: $((total - max_findings)) more findings in $abs"
  fi
  found=1
}

for file in "$@"; do
  lint_file "$file"
done

if [ "$found" = 1 ]; then
  echo "doc-lint: Kubernetes Documentation Style Guide: $guide_url"
fi

exit 0

# AGENTS.md Symlinks Design

## What

`.claude/CLAUDE.md` を唯一の実体（source of truth）とし、以下 2 つのシンボリックリンクを追加する。

- `.codex/AGENTS.md` → `../.claude/CLAUDE.md`
- `.gemini/AGENTS.md` → `../.claude/CLAUDE.md`

既存の `.codex/config.toml`、`.gemini/settings.json` は変更しない。

## Why

- codex はグローバル指示ファイルとして `~/.codex/AGENTS.md` を読む
- antigravity はグローバル指示ファイルとして `~/.gemini/AGENTS.md` を読む（Gemini 系ツールとして `.gemini` ディレクトリを共有するため）
- 同じ内容を複数ファイルに重複して書きたくないため、実体は `.claude/CLAUDE.md` に一本化し、他ツール向けにはシンボリックリンクで参照させる
- リポジトリのクローン先パスは環境ごとに異なるため、絶対パスではなく相対パスのシンボリックリンクにする。git はシンボリックリンクをそのまま追跡できる（mode 120000）ため、リポジトリ内で完結する

## Deployment note

実配置は本リポジトリ（dotfiles）ではなく [ansible repo](https://github.com/panicboat/ansible) が担当する。ansible 側がディレクトリ単位でシンボリックリンクしている場合はそのまま機能するが、ファイル単位で明示リストを持っている場合は `AGENTS.md` の追加を ansible repo 側にも反映する必要がある。この対応は本リポジトリの範囲外。

## Verification

- `git ls-files -s` で `.codex/AGENTS.md`、`.gemini/AGENTS.md` が symlink（120000）として認識されること
- `readlink .codex/AGENTS.md` / `readlink .gemini/AGENTS.md` が `../.claude/CLAUDE.md` を指すこと
- `cat .codex/AGENTS.md` / `cat .gemini/AGENTS.md` の内容が `.claude/CLAUDE.md` と一致すること

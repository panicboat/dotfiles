# Homebrew
[[ ":$PATH:" == *":/opt/homebrew/bin:"* ]] || export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"

# no match found
setopt +o nomatch

# history
setopt share_history
setopt inc_append_history
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_reduce_blanks
HISTFILE=${HOME}/.zsh_history
HISTSIZE=1000
SAVEHIST=100000

# alias
alias cat='bat -p'
alias ls='eza --time-style=long-iso -g'
alias ll='eza --time-style=long-iso -hgl --git'
alias la='eza --time-style=long-iso -ahgl --git'
alias l1='eza -1'
alias tree='eza -T --git-ignore'
alias rm='trash-put'
alias k='kubectl'

# initialization
eval "$(starship init zsh)"
# nodejs
export PATH="$HOME/.nodenv/shims:$PATH"
nodenv() { unfunction nodenv; eval "$(command nodenv init - zsh)"; nodenv "$@"; }
# ruby
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
rbenv() { unfunction rbenv; eval "$(command rbenv init - zsh)"; rbenv "$@"; }
# go
export GOENV_ROOT=$HOME/.goenv
export PATH="$GOENV_ROOT/bin:$GOENV_ROOT/shims:$PATH"
goenv() { unfunction goenv; eval "$(command goenv init -)"; goenv "$@"; }
# python
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
[[ -d $PYENV_ROOT/shims ]] && export PATH="$PYENV_ROOT/shims:$PATH"
pyenv() { unfunction pyenv; eval "$(command pyenv init -)"; pyenv "$@"; }
# docker
alias docker-stop='docker stop $(docker ps -q)'
alias docker-prune='docker system prune -a -f --volumes && docker volume prune -a -f'
# Antigravity
export PATH="$HOME/.antigravity/antigravity/bin:$PATH"
# aqua
export PATH="${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}/bin:$PATH"

# aoutocompletion
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
FPATH=/opt/homebrew/share/zsh-completions:$FPATH
FPATH=/opt/homebrew/share/zsh/site-functions:$FPATH

_kube_cache_dir=${ZDOTDIR:-$HOME}/.zsh/completions
if (( $+commands[kubectl] )); then
  if [[ ! -f $_kube_cache_dir/_kubectl || $commands[kubectl] -nt $_kube_cache_dir/_kubectl ]]; then
    mkdir -p $_kube_cache_dir
    kubectl completion zsh > $_kube_cache_dir/_kubectl
  fi
  FPATH=$_kube_cache_dir:$FPATH
fi
unset _kube_cache_dir

autoload -Uz compinit
_zcompdump=${ZDOTDIR:-$HOME}/.zcompdump
if [[ ! -f $_zcompdump || -n $_zcompdump(#qN.md+1) ]]; then
  compinit
else
  compinit -C
fi
unset _zcompdump
compaudit | xargs chmod g-w

# cdr
if [[ -n $(echo ${^fpath}/chpwd_recent_dirs(N)) && -n $(echo ${^fpath}/cdr(N)) ]]; then
  autoload -Uz chpwd_recent_dirs cdr add-zsh-hook
  add-zsh-hook chpwd chpwd_recent_dirs
  zstyle ':completion:*' recent-dirs-insert both
  zstyle ':chpwd:*' recent-dirs-default true
  zstyle ':chpwd:*' recent-dirs-max 1000
  zstyle ':chpwd:*' recent-dirs-file "$HOME/.cache/chpwd-recent-dirs"
fi

# peco

## Search from command history
function peco-select-history() {
  BUFFER=$(\history -n -r 1 | peco --query "$LBUFFER")
  CURSOR=$#BUFFER
  zle clear-screen
}
zle -N peco-select-history
bindkey '^r' peco-select-history

## Search and move directories from command history
function peco-get-destination-from-cdr() {
  cdr -l | \
  sed -e 's/^[[:digit:]]*[[:blank:]]*//' | \
  peco --query "$LBUFFER"
}
function peco-cdr() {
  local destination="$(peco-get-destination-from-cdr)"
  if [ -n "$destination" ]; then
    BUFFER="cd $destination"
    zle accept-line
  else
    zle reset-prompt
  fi
}
zle -N peco-cdr
bindkey '^e' peco-cdr

## Search and move directories under the current directory
function find_cd() {
  local selected_dir=$(find . -type d -name ".git*" -prune -prune -o -print | peco)
  if [ -n "$selected_dir" ]; then
    BUFFER="cd ${selected_dir}"
    zle accept-line
  fi
}
zle -N find_cd
bindkey '^f' find_cd

## alias
alias -g gb='git checkout $(git branch | sed -r "s/^[ \*]+//" | peco)'
alias de='docker exec -it $(docker ps | peco | cut -d " " -f 1) /bin/bash'

## function

function codex() {
  $HOME/.agents/skills/agmsg/scripts/drivers/types/codex/codex-shim.sh "$@"
}

function brew-update() {
  brew update && brew upgrade && brew upgrade --cask && brew cleanup && brew autoremove
}

function eks-login() {
  source "${HOME}/.script/eks-login.sh" "$@"
}

# no match found
setopt +o nomatch

# history
setopt hist_ignore_dups
setopt share_history
export HISTFILE=${HOME}/.zsh_history
export HISTSIZE=1000
export SAVEHIST=100000

# alias
alias cat='bat -p'
alias ls='eza --time-style=long-iso -g'
alias ll='eza --time-style=long-iso -hgl --git'
alias la='eza --time-style=long-iso -ahgl --git'
alias l1='eza -1'
alias tree='eza -T --git-ignore'
alias diff='delta'
alias rm='trash-put'

alias k='kubectl'

# initialization
eval "$(starship init zsh)"

# aoutocompletion
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
FPATH=/opt/homebrew/share/zsh-completions:$FPATH
FPATH=/opt/homebrew/share/zsh/site-functions:$FPATH
autoload -Uz compinit && compinit

source <(kubectl completion zsh)
compaudit | xargs chmod g-w

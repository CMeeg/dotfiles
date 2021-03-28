export ZSH="$HOME/.oh-my-zsh"

DEFAULT_USER=`whoami`

ZSH_THEME="agnoster"

plugins=(git)

source $ZSH/oh-my-zsh.sh

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

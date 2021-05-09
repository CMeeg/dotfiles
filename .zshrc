export ZSH="$HOME/.oh-my-zsh"

DEFAULT_USER=`whoami`

eval "$(oh-my-posh --init --shell zsh --config $HOME/.poshthemes/star.omp.json)"

plugins=(common-aliases git npm yarn z)

source $ZSH/oh-my-zsh.sh

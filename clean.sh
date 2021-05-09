#!/usr/bin/env bash

###
# This script is basically the inverse of install.sh
###

set -e

DOTFILES_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. "${DOTFILES_ROOT}/scripts/prompt-utils.sh"

clean_gitconfig () {
    if [ -f "${HOME}/.gitconfig" ]; then
        info "Cleaning .gitconfig"

        rm "${HOME}/.gitconfig"

        success "Cleaned .gitconfig"
    else
        success "No .gitconfig"
    fi
}

clean_zsh () {
    if [ -d "${HOME}/.oh-my-zsh" ]; then
        info "Cleaning ohmyzsh"

        sh "${HOME}/.oh-my-zsh/tools/uninstall.sh"

        success "Cleaned .zshrc"
    else
        success "No ohmyzsh"
    fi

    if [ -d "${HOME}/.poshthemes" ]; then
        success "Found ohmyposh"
        info "Cleaning ohmyposh"

        #TODO: Couldn't get this to work - permissions issues with chmod
        #chmod -x /usr/local/bin/oh-my-posh
        #rm /usr/local/bin/oh-my-posh

        chmod u-rw "${HOME}/.poshthemes/"*.json
        rm -r "${HOME}/.poshthemes"

        success "Cleaned ohmyposh"
    else
        success "No ohmyposh"
    fi

    info "Setting shell to bash"

    chsh -s $(which bash)

    success "Set shell to bash"
}

confirm "Cleaning" "Aborting"

clean_gitconfig

clean_zsh

success "All done!"

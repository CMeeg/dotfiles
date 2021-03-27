#!/usr/bin/env bash

###
# This script is basically the inverse of install.sh
###

DOTFILES_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

set -e

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
}

confirm "Cleaning" "Aborting"

clean_gitconfig

clean_zsh

success "All done!"
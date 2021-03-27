#!/usr/bin/env bash

###
# This script installs common dev tools and configures them
#
# A lot of this copied from or inspired by
# https://github.com/holman/dotfiles
# https://github.com/benmatselby/dotfiles
# https://github.com/driesvints/dotfiles
###

DOTFILES_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

set -e

. "${DOTFILES_ROOT}/scripts/prompt-utils.sh"

setup_gitconfig () {
    if [ -f "${HOME}/.gitconfig" ]; then
        success "Found .gitconfig"
    else
        info "Setting up .gitconfig"

        cp "${DOTFILES_ROOT}/.gitconfig" "${HOME}/.gitconfig"

        user " - What is your github author name?"
        read -e git_authorname
        user " - What is your github author email?"
        read -e git_authoremail

        git config --global user.name "$git_authorname"
        git config --global user.email "$git_authoremail"

        if [[ -v WSL_DISTRO_NAME ]]; then
            git config --global credential.helper "/mnt/c/Program\\ Files/Git/mingw64/libexec/git-core/git-credential-wincred.exe"
        fi

        success "Setup .gitconfig"
    fi
}

setup_zsh () {
    if test $(which zsh); then
        success "Found zsh"
    else
        info "Installing zsh"

        apt install zsh

        chsh -s $(which zsh)

        success "Installed zsh"
    fi

    if [ -d "${HOME}/.oh-my-zsh" ]; then
        success "Found ohmyzsh"
    else
        info "Installing ohmyzsh"

        sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        #sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

        cp "${DOTFILES_ROOT}/.zshrc" "${HOME}/.zshrc"

        zsh

        success "Installed ohmyzsh"
    fi
}

setup_gitconfig

# Do this last as it configures the shell
setup_zsh

success "All done!"
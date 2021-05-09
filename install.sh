#!/usr/bin/env bash

###
# This script installs common dev tools and configures them
#
# A lot of this copied from or inspired by
# https://github.com/holman/dotfiles
# https://github.com/benmatselby/dotfiles
# https://github.com/driesvints/dotfiles
###

set -e

DOTFILES_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. "${DOTFILES_ROOT}/scripts/prompt-utils.sh"

install () {
    if command -v $1 > /dev/null 2>&1; then
        info "$1 is installed"
    else
        info "Installing $1"

        apt-get install $1 -y

        success "$1 installed"
    fi
}

setup_gitconfig () {
    if [ -f "${HOME}/.gitconfig" ]; then
        success "Found .gitconfig"
    else
        if [[ -v REMOTE_CONTAINERS ]]; then
            # Remote containers takes care of gitconfig for us
            success "Skipped .gitconfig - remote container"
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
    fi
}

setup_zshrc () {
    info "Setting up .zshrc"

    cp "${DOTFILES_ROOT}/.zshrc" "${HOME}/.zshrc"

    success "Setup .zshrc"
}

setup_zsh () {
    install zsh

    if [ "${SHELL}" = $(which zsh) ]; then
        info "Shell is zsh"
    else
        if [[ -v REMOTE_CONTAINERS ]]; then
            # Remote containers allow you to set the shell in devcontainer.json, which is better than doing it here because this will probably require admin rights and cause the script to pause execution
            success "Skipped setting shell to zsh - remote container"
        else
            info "Setting shell to zsh"

            chsh -s $(which zsh)

            success "Set shell to zsh"
        fi
    fi

    if [ -d "${HOME}/.poshthemes" ]; then
        success "Found ohmyposh"
    else
        info "Installing ohmyposh"

        if command -v oh-my-posh > /dev/null 2>&1; then
            info "Found ohmyposh"
        else
            wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh
            chmod +x /usr/local/bin/oh-my-posh

            success "Installed ohmyposh"
        fi

        install unzip

        mkdir "${HOME}/.poshthemes"
        wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip -O "${HOME}/.poshthemes/themes.zip"
        unzip "${HOME}/.poshthemes/themes.zip" -d "${HOME}/.poshthemes"
        chmod u+rw "${HOME}/.poshthemes/"*.json
        rm "${HOME}/.poshthemes/themes.zip"

        success "Installed ohmyposh themes"
    fi

    if [ -d "${HOME}/.oh-my-zsh" ]; then
        success "Found ohmyzsh"
    else
        info "Installing ohmyzsh"

        sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

        # ohmyzsh adds its own .zshrc so we want to overwrite it

        setup_zshrc

        zsh

        success "Installed ohmyzsh"
    fi

    if [ -f "${HOME}/.zshrc" ]; then
        if [[ -v REMOTE_CONTAINERS ]]; then
            # Some remote containers have ohmyzsh and .zshrc pre-installed so we want to overwrite it
            setup_zshrc
        else
            success "Found .zshrc"
        fi
    else
        setup_zshrc
    fi
}

setup_gitconfig

# Do this last as it configures the shell
setup_zsh

success "All done!"

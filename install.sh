#!/usr/bin/env bash
set -euo pipefail

DOTFILES_REPO="${HOME}/.dotfiles"
NODE_VERSION="24"
DRY_RUN=false

# Colors
RESET='\033[0m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'

# ---------- Output ----------

print_status() { printf "${CYAN}%s${RESET}\n" "• $1"; }
print_ok()     { printf "${GREEN}%s${RESET}\n" "  ✓ $1"; }
print_skip()   { printf "${YELLOW}%s${RESET}\n" "  - $1"; }
print_warn()   { printf "${YELLOW}%s${RESET}\n" "  ! $1"; }
print_dry()    { printf "${BLUE}%s${RESET}\n" "  ~ $1"; }

run() {
    if [ "$DRY_RUN" = true ]; then
        print_dry "$1"
        return 0
    fi
    if ! bash -c "$1"; then
        local ec=$?
        print_warn "Command failed (exit code $ec): $1"
        exit "$ec"
    fi
}

# ---------- Helpers ----------

is_cmd() { command -v "$1" &>/dev/null; }

is_apt_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

is_symlinked() {
    local target="$1" expected_source="$2"
    [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$expected_source")" ]
}

# ---------- Sections ----------

update_system() {
    print_status "Updating system packages..."
    run "sudo apt update"
    run "sudo apt upgrade -y"
    print_ok "System packages updated"
}

install_packages() {
    print_status "Installing base packages..."
    local packages=(build-essential curl fonts-jetbrains-mono git stow unzip wget)
    local missing=()

    for pkg in "${packages[@]}"; do
        if ! is_apt_installed "$pkg"; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        print_skip "All base packages are already installed"
        return
    fi
    run "sudo apt install -y ${missing[*]}"
    print_ok "Base packages installed"
}

install_starship() {
    print_status "Installing Starship..."
    if is_cmd starship; then
        print_skip "Starship is already installed"
        return
    fi
    run "curl -sS https://starship.rs/install.sh | sh"
    print_ok "Starship installed"
}

stow_base_dotfiles() {
    print_status "Stowing base dotfiles (bash, git, starship)..."
    if is_symlinked "$HOME/.bashrc" "$DOTFILES_REPO/bash/.bashrc" &&
       is_symlinked "$HOME/.gitconfig" "$DOTFILES_REPO/git/.gitconfig" &&
       is_symlinked "$HOME/.config/starship.toml" "$DOTFILES_REPO/starship/.config/starship.toml"; then
        print_skip "Base dotfiles (bash, git, starship) are already stowed"
        return
    fi
    run "cd $DOTFILES_REPO && stow --adopt --no-folding -v bash git starship"
    if [ "$DRY_RUN" = true ]; then
        print_dry "source $HOME/.bashrc"
    else
        source "$HOME/.bashrc" 2>/dev/null || true
    fi
    print_ok "Base dotfiles stowed"
    print_warn "Review any changes with 'git diff' in $DOTFILES_REPO"
}

create_projects_dir() {
    print_status "Creating ~/projects directory..."
    if [ -d "$HOME/projects" ]; then
        print_skip "~/projects directory already exists"
        return
    fi
    run "mkdir -p $HOME/projects"
    print_ok "~/projects directory created"
}

install_gitkraken() {
    print_status "Installing GitKraken..."
    if is_apt_installed gitkraken; then
        print_skip "GitKraken is already installed"
        return
    fi
    run "wget -O /tmp/gitkraken-amd64.deb https://release.gitkraken.com/linux/gitkraken-amd64.deb && sudo apt install -y /tmp/gitkraken-amd64.deb"
    print_ok "GitKraken installed"
    print_warn "Run 'gitkraken' and follow setup steps in gitkraken/README.md"
}

install_node() {
    print_status "Installing fnm, Node $NODE_VERSION, and pnpm..."
    if is_cmd fnm; then
        print_skip "fnm is already installed"
        return
    fi
    run "curl -o- https://fnm.vercel.app/install | bash"
    # fnm install script writes to .bashrc, but sourcing .bashrc in a
    # non-interactive script is a no-op — add fnm to PATH directly
    if [ "$DRY_RUN" = true ]; then
        print_dry "Add fnm to PATH"
    else
        export FNM_PATH="$HOME/.local/share/fnm"
        if [ -d "$FNM_PATH" ]; then
            export PATH="$FNM_PATH:$PATH"
        fi
    fi
    run "fnm install $NODE_VERSION"
    run "corepack enable pnpm"
    print_ok "fnm, Node $NODE_VERSION, and pnpm installed"
}

install_bun() {
    print_status "Installing Bun..."
    if is_cmd bun; then
        print_skip "Bun is already installed"
        return
    fi
    run "curl -fsSL https://bun.sh/install | bash"
    if [ "$DRY_RUN" = true ]; then
        print_dry "source $HOME/.bashrc"
    else
        source "$HOME/.bashrc" 2>/dev/null || true
    fi
    print_ok "Bun installed"
}

install_chrome() {
    print_status "Installing Google Chrome..."
    if is_apt_installed google-chrome-stable; then
        print_skip "Google Chrome is already installed"
        return
    fi
    run "wget -O /tmp/google-chrome-stable_current_amd64.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && sudo apt install -y /tmp/google-chrome-stable_current_amd64.deb"
    print_ok "Google Chrome installed"
}

install_opencode() {
    print_status "Installing opencode..."
    if is_cmd opencode; then
        print_skip "opencode is already installed"
        return
    fi
    run "curl -fsSL https://opencode.ai/install | bash"
    print_ok "opencode installed"
}

install_superpowers() {
    print_status "Installing Superpowers for opencode..."

    local superpowers_dir="$HOME/.local/share/opencode/packages/superpowers"
    local config_file="$HOME/.config/opencode/opencode.jsonc"

    # Clone if not already present
    if [ -d "$superpowers_dir" ]; then
        print_skip "Superpowers is already cloned"
    else
        run "git clone https://github.com/obra/superpowers.git $superpowers_dir"
        print_ok "Superpowers cloned"
    fi

    # Add superpowers to opencode.jsonc plugin array if needed
    if [ ! -f "$config_file" ]; then
        print_skip "opencode.jsonc not found — stow will create it with superpowers configured"
        return
    fi

    if [ -L "$config_file" ]; then
        # Symlinked — already managed by stow
        if grep -q "superpowers" "$config_file" 2>/dev/null; then
            print_skip "Superpowers already configured in opencode.jsonc"
        else
            print_warn "opencode.jsonc symlink is missing superpowers — update the repo file"
        fi
        return
    fi

    # Regular file (not stowed) — patch before stow --adopt replaces it
    if grep -q "superpowers" "$config_file" 2>/dev/null; then
        print_skip "Superpowers already configured in opencode.jsonc"
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        print_dry "Add superpowers to plugin array in $config_file"
        return
    fi

    if ! is_cmd node; then
        print_warn "Node.js not found — cannot patch opencode.jsonc automatically"
        print_warn "Manually add superpowers to $config_file"
        return
    fi

    node -e '
        const fs = require("fs");
        const p = process.argv[1];
        let c = fs.readFileSync(p, "utf8");
        let j = JSON.parse(c);
        if (!Array.isArray(j.plugin)) j.plugin = [];
        const pkg = "~/.local/share/opencode/packages/superpowers";
        if (!j.plugin.includes(pkg)) {
            j.plugin.push(pkg);
            fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
        }
    ' "$config_file"

    print_ok "Superpowers added to opencode.jsonc"
}

install_opendesign() {
    print_status "Installing OpenDesign..."

    local opendesign_dir="$HOME/.opendesign"
    local od_binary="$opendesign_dir/node_modules/.bin/od"

    if [ -x "$od_binary" ]; then
        print_skip "OpenDesign is already installed"
        return
    fi

    run "mkdir -p $opendesign_dir"
    if [ -d "$opendesign_dir/.git" ]; then
        print_skip "OpenDesign repo already cloned"
    else
        run "git clone https://github.com/nexu-io/open-design.git $opendesign_dir"
        print_ok "OpenDesign repo cloned"
    fi

    run "cd $opendesign_dir && corepack enable && pnpm install && pnpm --filter @open-design/web build"
    print_ok "OpenDesign installed"
}

stow_opencode_dotfiles() {
    print_status "Stowing opencode dotfiles (agents, opencode)..."
    if is_symlinked "$HOME/.agents/skills/find-docs/SKILL.md" "$DOTFILES_REPO/agents/.agents/skills/find-docs/SKILL.md" &&
       is_symlinked "$HOME/.config/opencode/opencode.jsonc" "$DOTFILES_REPO/opencode/.config/opencode/opencode.jsonc"; then
        print_skip "opencode dotfiles (agents, opencode) are already stowed"
        return
    fi
    run "cd $DOTFILES_REPO && stow --adopt --no-folding -v agents opencode"
    print_ok "opencode dotfiles stowed"
    print_warn "Review any changes with 'git diff' in $DOTFILES_REPO"
}

# ---------- Main ----------

main() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=true ;;
            -h|--help)
                echo "Usage: $0 [--dry-run]"
                echo ""
                echo "Automates the Debian setup described in linux/README.md."
                echo "Idempotent — safe to run multiple times."
                exit 0
                ;;
        esac
    done

    echo ""
    printf "${BOLD}dotfiles installer${RESET}\n"
    [ "$DRY_RUN" = true ] && printf "${BLUE}Dry-run mode — no changes will be made${RESET}\n"
    echo ""

    # Keep sudo credentials alive: prompt once at start, then refresh every 60s
    # The background loop exits automatically when this script process ends
    if [ "$DRY_RUN" = false ]; then
        sudo -v
        while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    fi

    update_system
    install_packages
    install_starship
    stow_base_dotfiles
    create_projects_dir
    install_gitkraken
    install_node
    install_bun
    install_chrome
    install_opencode
    install_superpowers
    install_opendesign
    stow_opencode_dotfiles

    echo ""
    printf "${GREEN}✨ ${BOLD}Done.${RESET}\n"

    # source in a subshell only affects the subshell, so the user must reload
    # in their own terminal to pick up aliases, fnm PATH, starship, etc.
    printf "${BOLD}  → Run 'source ~/.bashrc' to reload your shell.${RESET}\n"
}

main "$@"

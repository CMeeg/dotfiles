#!/usr/bin/env bash
set -euo pipefail

DOTFILES_REPO="${HOME}/.dotfiles"
DRY_RUN=false
SKIP_RETIRE=false

# shellcheck source=lib/retire.sh
source "$DOTFILES_REPO/lib/retire.sh"
# shellcheck source=lib/gitkraken.sh
source "$DOTFILES_REPO/lib/gitkraken.sh"

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
    local ec=0
    # pipefail: a failed download in 'curl … | bash' must fail the step, not pass it
    bash -o pipefail -c "$1" || ec=$?
    if [ "$ec" -ne 0 ]; then
        print_warn "Command failed (exit code $ec): $1"
        exit "$ec"
    fi
}

# ---------- Helpers ----------

is_cmd() { command -v "$1" &>/dev/null; }

# Prints the newest Node LTS version known to fnm (e.g. v26.13.0); returns 1 if none
latest_node_lts() {
    local v
    v=$(fnm list-remote --lts 2>/dev/null | tail -n1 | awk '{print $1}')
    [ -n "$v" ] || return 1
    echo "$v"
}

is_apt_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

is_symlinked() {
    local target="$1" expected_source="$2"
    [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$expected_source")" ]
}

is_opencode_v2() {
    is_cmd opencode || return 1
    opencode --version 2>/dev/null | grep -qE 'v?2\.'
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
    local packages=(build-essential curl fonts-jetbrains-mono libnss3-tools jq python-is-python3 python3 stow unzip wget)
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
    run "curl -sS https://starship.rs/install.sh | sh -s -- -y"
    print_ok "Starship installed"
}

install_superfile() {
    print_status "Installing superfile..."
    if is_cmd spf; then
        print_skip "superfile is already installed"
        return
    fi
    run 'bash -c "$(curl -sLo- https://superfile.dev/install.sh)"'
    print_ok "superfile installed (run 'spf' to start)"
}

install_herdr() {
    print_status "Installing herdr..."
    if is_cmd herdr; then
        print_skip "herdr is already installed"
        return
    fi
    run "curl -fsSL https://herdr.dev/install.sh | sh"
    print_ok "herdr installed (run 'herdr' to start)"
}

stow_base_dotfiles() {
    print_status "Stowing base dotfiles (bash, git, starship, superfile, herdr)..."
    if is_symlinked "$HOME/.bashrc" "$DOTFILES_REPO/bash/.bashrc" &&
       is_symlinked "$HOME/.gitconfig" "$DOTFILES_REPO/git/.gitconfig" &&
       is_symlinked "$HOME/.config/starship.toml" "$DOTFILES_REPO/starship/.config/starship.toml" &&
       is_symlinked "$HOME/.config/superfile/config.toml" "$DOTFILES_REPO/superfile/.config/superfile/config.toml" &&
       is_symlinked "$HOME/.config/herdr/config.toml" "$DOTFILES_REPO/herdr/.config/herdr/config.toml"; then
        print_skip "Base dotfiles (bash, git, starship, superfile, herdr) are already stowed"
        return
    fi
    run "cd $DOTFILES_REPO && stow --adopt --no-folding -v bash git starship superfile herdr"
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
    run "wget -O /tmp/gitkraken-amd64.deb $GITKRAKEN_DEB_URL && sudo apt install -y /tmp/gitkraken-amd64.deb"
    print_ok "GitKraken installed"
    print_warn "Run 'gitkraken' and follow setup steps in gitkraken/README.md"
}

install_node() {
    print_status "Installing fnm and Node (latest LTS)..."
    if is_cmd fnm; then
        print_skip "fnm is already installed"
        return
    fi
    # --skip-shell: bash/.bashrc (stowed) already sets up fnm, so the installer must not append to it
    run "curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell"
    # Sourcing .bashrc in a non-interactive script is a no-op — add fnm to PATH directly
    if [ "$DRY_RUN" = true ]; then
        print_dry "Add fnm to PATH"
        print_dry "fnm install <latest LTS> && fnm default <latest LTS>"
        print_ok "fnm and Node (latest LTS) installed"
        return
    fi
    export FNM_PATH="$HOME/.local/share/fnm"
    if [ -d "$FNM_PATH" ]; then
        export PATH="$FNM_PATH:$PATH"
    fi
    local lts
    if ! lts=$(latest_node_lts); then
        print_warn "Couldn't find the latest Node LTS — run 'fnm install --lts' later"
        return
    fi
    run "fnm install $lts && fnm default $lts"
    print_ok "fnm and Node $lts installed"
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

install_caddy() {
    print_status "Installing Caddy..."
    local just_installed=false
    if is_apt_installed caddy; then
        print_skip "Caddy is already installed"
    else
        # Adds Caddy's apt repo so 'apt upgrade' keeps it updated
        run "sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl"
        run "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg"
        run "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null"
        run "sudo chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list"
        run "sudo apt update"
        run "sudo apt install -y caddy"
        print_ok "Caddy installed"
        just_installed=true
    fi

    # The package starts a 'caddy' systemd service serving a default page on :80,
    # which blocks projects running 'caddy run' themselves. Upgrades keep it disabled.
    if [ "$just_installed" = true ] ||
       systemctl is-enabled --quiet caddy 2>/dev/null ||
       systemctl is-active --quiet caddy 2>/dev/null; then
        run "sudo systemctl disable --now caddy"
        print_ok "Caddy systemd service disabled"
    else
        print_skip "Caddy systemd service is already disabled"
    fi
}

allow_unprivileged_low_ports() {
    print_status "Allowing unprivileged processes to bind ports 80 and above..."
    # Lets 'caddy run' (or any dev server) bind 80/443 without root. Unlike setcap,
    # this survives binary upgrades. Fine for a dev machine.
    local conf="/etc/sysctl.d/50-unprivileged-ports.conf"
    local setting="net.ipv4.ip_unprivileged_port_start=80"
    if grep -qxF "$setting" "$conf" 2>/dev/null; then
        print_skip "Unprivileged port start is already set to 80"
        return
    fi
    run "echo '$setting' | sudo tee $conf >/dev/null"
    run "sudo sysctl --system >/dev/null"
    print_ok "Unprivileged port start set to 80"
}

install_aspire() {
    print_status "Installing Aspire CLI..."
    # Only the install script's location counts, so every machine installs Aspire the same way
    # (a .NET global tool install is removed by the retire steps)
    if [ -x "$HOME/.aspire/bin/aspire" ]; then
        print_skip "Aspire CLI is already installed"
        return
    fi
    # --skip-path: ~/.bashrc is stowed, so PATH is set there instead of letting the installer append to it
    run "curl -sSL https://aspire.dev/install.sh | bash -s -- --skip-path"
    print_ok "Aspire CLI installed"
}

install_opencode() {
    print_status "Installing opencode..."
    if is_opencode_v2; then
        print_skip "opencode v2 is already installed"
        return
    fi
    if is_cmd opencode; then
        print_warn "opencode v1 detected — the installer will replace it with v2"
    fi
    run "curl -fsSL https://opencode.ai/v2/install | bash"
    print_ok "opencode installed"
}

install_claude_code() {
    print_status "Installing Claude Code..."
    if is_cmd claude; then
        print_skip "Claude Code is already installed"
        return
    fi
    run "curl -fsSL https://claude.ai/install.sh | bash"
    print_ok "Claude Code installed"
    print_warn "Run 'claude' and follow the sign-in steps — see claude/README.md"
}

stow_opencode_dotfiles() {
    print_status "Stowing opencode dotfiles (opencode)..."
    if is_symlinked "$HOME/.config/opencode/opencode.jsonc" "$DOTFILES_REPO/opencode/.config/opencode/opencode.jsonc"; then
        print_skip "opencode dotfiles (opencode) are already stowed"
        return
    fi
    run "cd $DOTFILES_REPO && stow --adopt --no-folding -v opencode"
    print_ok "opencode dotfiles stowed"
    print_warn "Review any changes with 'git diff' in $DOTFILES_REPO"
}

stow_claude_dotfiles() {
    print_status "Stowing Claude Code dotfiles (claude)..."
    if is_symlinked "$HOME/.claude/settings.json" "$DOTFILES_REPO/claude/.claude/settings.json"; then
        print_skip "Claude Code dotfiles (claude) are already stowed"
        return
    fi
    # --no-folding keeps ~/.claude a real directory so credentials/history never land in the repo
    run "cd $DOTFILES_REPO && stow --adopt --no-folding -v claude"
    print_ok "Claude Code dotfiles stowed"
    print_warn "Review any changes with 'git diff' in $DOTFILES_REPO"
}

# ---------- Main ----------

main() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=true ;;
            --skip-retire) SKIP_RETIRE=true ;;
            -h|--help)
                echo "Usage: $0 [--dry-run] [--skip-retire]"
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

    if [ "$SKIP_RETIRE" = true ]; then
        print_skip "Skipping retire steps (--skip-retire)"
    else
        run_retire_steps
    fi
    update_system
    install_packages
    install_starship
    install_superfile
    install_herdr
    stow_base_dotfiles
    create_projects_dir
    install_gitkraken
    install_node
    install_chrome
    install_caddy
    allow_unprivileged_low_ports
    install_aspire
    install_opencode
    install_claude_code
    stow_opencode_dotfiles
    stow_claude_dotfiles

    echo ""
    printf "${GREEN}✨ ${BOLD}Done.${RESET}\n"

    # source in a subshell only affects the subshell, so the user must reload
    # in their own terminal to pick up aliases, fnm PATH, starship, etc.
    printf "${BOLD}  → Run 'source ~/.bashrc' to reload your shell.${RESET}\n"
}

main "$@"

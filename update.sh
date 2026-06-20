#!/usr/bin/env bash
set -euo pipefail

DOTFILES_REPO="${HOME}/.dotfiles"
SUPERPOWERS_DIR="${HOME}/.local/share/opencode/packages/superpowers"
OPENDESIGN_DIR="${HOME}/.opendesign"
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

is_repo_behind() {
    local repo_dir="$1"
    (cd "$repo_dir" && git fetch origin) 2>/dev/null || return 1
    local behind
    behind=$(cd "$repo_dir" && git rev-list --count HEAD..@{u} 2>/dev/null) || return 1
    [ "$behind" -gt 0 ]
}

# ---------- Sections ----------

update_system() {
    print_status "Updating system packages..."
    run "sudo apt update"
    run "sudo apt upgrade -y"
    print_ok "System packages updated"
}

update_bun() {
    print_status "Updating Bun..."
    if ! is_cmd bun; then
        print_skip "Bun is not installed — skipping"
        return
    fi
    run "bun upgrade"
    print_ok "Bun updated"
}

update_starship() {
    print_status "Updating Starship..."
    if ! is_cmd starship; then
        print_skip "Starship is not installed — skipping"
        return
    fi
    run "curl -sS https://starship.rs/install.sh | sh"
    print_ok "Starship updated"
}

update_superpowers() {
    print_status "Updating Superpowers..."
    if [ ! -d "$SUPERPOWERS_DIR/.git" ]; then
        print_skip "Superpowers is not installed — skipping"
        return
    fi
    if ! is_repo_behind "$SUPERPOWERS_DIR"; then
        print_skip "Superpowers is already up to date"
        return
    fi
    run "cd $SUPERPOWERS_DIR && git pull"
    print_ok "Superpowers updated"
}

update_opendesign() {
    print_status "Updating OpenDesign..."
    if [ ! -d "$OPENDESIGN_DIR/.git" ]; then
        print_skip "OpenDesign is not installed — skipping"
        return
    fi
    if ! is_repo_behind "$OPENDESIGN_DIR"; then
        print_skip "OpenDesign is already up to date"
        return
    fi
    if pgrep -f "open-design" > /dev/null 2>&1; then
        run "pkill -f open-design"
    fi
    run "cd $OPENDESIGN_DIR && git stash && git pull && pnpm install && pnpm --filter @open-design/web build"
    print_ok "OpenDesign updated"
}

restow() {
    print_status "Restowing dotfiles..."
    if [ ! -d "$DOTFILES_REPO/.git" ]; then
        print_warn "Dotfiles repo not found at $DOTFILES_REPO — skipping restow"
        return
    fi
    run "cd $DOTFILES_REPO && git stash && git pull && stow --adopt --no-folding -v agents bash git opencode starship && git stash pop"
    print_ok "Dotfiles restowed"
    print_warn "Review any changes with 'git diff' in $DOTFILES_REPO"
    print_warn "If changes look good, commit and push them"
}

# ---------- Main ----------

main() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=true ;;
            -h|--help)
                echo "Usage: $0 [--dry-run]"
                echo ""
                echo "Automates the update steps described in linux/README.md."
                echo "Idempotent — safe to run multiple times."
                exit 0
                ;;
        esac
    done

    echo ""
    printf "${BOLD}dotfiles updater${RESET}\n"
    [ "$DRY_RUN" = true ] && printf "${BLUE}Dry-run mode — no changes will be made${RESET}\n"
    echo ""

    # Keep sudo credentials alive
    if [ "$DRY_RUN" = false ]; then
        sudo -v
        while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    fi

    update_system
    update_bun
    update_starship
    update_superpowers
    update_opendesign
    restow

    echo ""
    printf "${GREEN}✨ ${BOLD}Done.${RESET}\n"
    printf "${BOLD}  → Run 'source ~/.bashrc' to reload your shell.${RESET}\n"
    printf "${BOLD}  → Review dotfiles changes with 'cd ~/.dotfiles && git diff'${RESET}\n"
}

main "$@"

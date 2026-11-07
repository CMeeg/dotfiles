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
    local ec=0
    bash -c "$1" || ec=$?
    if [ "$ec" -ne 0 ]; then
        print_warn "Command failed (exit code $ec): $1"
        exit "$ec"
    fi
}

# ---------- Helpers ----------

is_cmd() { command -v "$1" &>/dev/null; }

is_repo_behind() {
    local repo_dir="$1"
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
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
    run "curl -sS https://starship.rs/install.sh | sh -s -- -y"
    print_ok "Starship updated"
}

update_superfile() {
    print_status "Updating superfile..."
    if ! is_cmd spf; then
        print_skip "superfile is not installed — skipping"
        return
    fi
    run 'bash -c "$(curl -sLo- https://superfile.dev/install.sh)"'
    print_ok "superfile updated"
}

update_herdr() {
    print_status "Updating herdr..."
    if ! is_cmd herdr; then
        print_skip "herdr is not installed — skipping"
        return
    fi
    # herdr refuses to update from inside one of its own sessions
    if [ -n "${HERDR_PANE_ID:-}" ]; then
        print_warn "Running inside a herdr session — skipping (detach and run 'herdr update')"
        return
    fi
    run "herdr update"
    print_ok "herdr updated"
}

update_aspire() {
    print_status "Updating Aspire CLI..."
    if [ ! -x "$HOME/.aspire/bin/aspire" ]; then
        print_skip "Aspire CLI is not installed — skipping"
        return
    fi
    # Re-running the installer fetches the latest stable release
    run "curl -sSL https://aspire.dev/install.sh | bash -s -- --skip-path"
    print_ok "Aspire CLI updated"
}

update_opencode() {
    print_status "Updating OpenCode..."
    if ! is_cmd opencode; then
        print_skip "OpenCode is not installed — skipping"
        return
    fi
    run "opencode upgrade"
    print_ok "OpenCode updated"
}

update_claude_code() {
    print_status "Updating Claude Code..."
    if ! is_cmd claude; then
        print_skip "Claude Code is not installed — skipping"
        return
    fi
    run "claude update"
    print_ok "Claude Code updated"
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
    run "cd $OPENDESIGN_DIR && git stash && git pull --ff-only && yes | pnpm install && pnpm --filter @open-design/web build"
    run "nohup $OPENDESIGN_DIR/node_modules/.bin/od --port 7456 --no-open >/dev/null 2>&1 & disown"
    print_ok "OpenDesign updated"
    print_ok "OpenDesign daemon restarted (http://127.0.0.1:7456)"
}

restow() {
    print_status "Restowing dotfiles..."
    if [ ! -d "$DOTFILES_REPO/.git" ]; then
        print_warn "Dotfiles repo not found at $DOTFILES_REPO — skipping restow"
        return
    fi
    local packages="bash git opencode starship superfile herdr"
    if [ "$DRY_RUN" = true ]; then
        print_dry "cd $DOTFILES_REPO && git stash (if needed) && git pull && git stash pop"
        print_dry "stow --adopt --no-folding -v $packages"
        return
    fi

    # Stash local changes so the pull can fast-forward, and always put them back
    # BEFORE stowing — otherwise packages that only exist locally are missing
    local stashed=false
    if [ -n "$(git -C "$DOTFILES_REPO" status --porcelain --untracked-files=no)" ]; then
        if ! git -C "$DOTFILES_REPO" stash push -m "update.sh restow"; then
            print_warn "Could not stash local changes — skipping restow"
            return
        fi
        stashed=true
    fi
    if ! git -C "$DOTFILES_REPO" pull; then
        print_warn "git pull failed — restowing the local copy as-is"
    fi
    if [ "$stashed" = true ] && ! git -C "$DOTFILES_REPO" stash pop; then
        print_warn "Could not re-apply local changes — they are still in 'git stash list'"
        print_warn "Resolve the conflict, run 'git stash drop', then restow manually"
        return
    fi

    if ! (cd "$DOTFILES_REPO" && stow --adopt --no-folding -v $packages); then
        print_warn "stow failed — see the errors above"
        return
    fi
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
    update_superfile
    update_herdr
    update_aspire
    update_opencode
    update_claude_code
    update_superpowers
    update_opendesign
    restow

    echo ""
    printf "${GREEN}✨ ${BOLD}Done.${RESET}\n"
    printf "${BOLD}  → Run 'source ~/.bashrc' to reload your shell.${RESET}\n"
    printf "${BOLD}  → Review dotfiles changes with 'cd ~/.dotfiles && git diff'${RESET}\n"
}

main "$@"

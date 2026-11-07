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

# ---------- Sections ----------

update_system() {
    print_status "Updating system packages..."
    run "sudo apt update"
    run "sudo apt upgrade -y"
    print_ok "System packages updated"
}

update_gitkraken() {
    print_status "Updating GitKraken..."
    if ! is_apt_installed gitkraken; then
        print_skip "GitKraken is not installed — skipping"
        return
    fi
    # Read-only lookup (one small request), so it runs in dry-run too
    local installed latest
    installed=$(dpkg-query -W -f='${Version}' gitkraken)
    if ! latest=$(gitkraken_latest_version); then
        print_warn "Couldn't work out the latest GitKraken version — skipping"
        return
    fi
    if ! gitkraken_needs_update "$installed" "$latest"; then
        print_skip "GitKraken is already up to date ($latest)"
        return
    fi
    run "wget -O /tmp/gitkraken-amd64.deb $GITKRAKEN_DEB_URL && sudo apt install -y /tmp/gitkraken-amd64.deb"
    print_ok "GitKraken updated to $latest"
}

update_node() {
    print_status "Updating fnm and Node (latest LTS)..."
    if ! is_cmd fnm; then
        print_skip "fnm is not installed — skipping"
        return
    fi
    # fnm has no self-update command; re-running the installer updates the binary.
    # --skip-shell: bash/.bashrc (stowed) already sets up fnm
    run "curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell"
    print_ok "fnm updated"

    # Read-only lookup, so it runs in dry-run too
    local lts default
    if ! lts=$(latest_node_lts); then
        print_warn "Couldn't find the latest Node LTS — skipping"
        return
    fi
    # Compare against the default alias, not 'fnm current', which follows .node-version files
    default=$(fnm list 2>/dev/null | awk '/ default/{print $2}')
    if [ "$default" = "$lts" ]; then
        print_skip "Node $lts (latest LTS) is already the default"
        return
    fi
    run "fnm install $lts && fnm default $lts"
    print_ok "Node $lts (latest LTS) is now the default — older versions are still installed"
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
        print_skip "Aspire CLI is not installed — skipping (run ./install.sh to install it)"
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

restow() {
    print_status "Restowing dotfiles..."
    if [ ! -d "$DOTFILES_REPO/.git" ]; then
        print_warn "Dotfiles repo not found at $DOTFILES_REPO — skipping restow"
        return
    fi
    local packages="bash git opencode starship superfile herdr claude"
    if [ "$DRY_RUN" = true ]; then
        print_dry "cd $DOTFILES_REPO && git stash (if needed) && git pull && git stash pop"
        print_dry "stow --adopt --no-folding -v $packages"
        retire_dangling_stow_links
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
    # A pull can move or delete files that existing links point at
    retire_dangling_stow_links
    print_warn "Review any changes with 'git diff' in $DOTFILES_REPO"
    print_warn "If changes look good, commit and push them"
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

    if [ "$SKIP_RETIRE" = true ]; then
        print_skip "Skipping retire steps (--skip-retire)"
    else
        run_retire_steps
    fi
    update_system
    update_gitkraken
    update_node
    update_starship
    update_superfile
    update_herdr
    update_aspire
    update_opencode
    update_claude_code
    restow

    echo ""
    printf "${GREEN}✨ ${BOLD}Done.${RESET}\n"
    printf "${BOLD}  → Run 'source ~/.bashrc' to reload your shell.${RESET}\n"
    printf "${BOLD}  → Review dotfiles changes with 'cd ~/.dotfiles && git diff'${RESET}\n"
}

main "$@"

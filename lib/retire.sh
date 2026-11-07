# Retire steps: remove tools and files that this repo no longer installs or manages.
#
# Sourced by install.sh and update.sh. The caller provides the print_* helpers,
# run, DRY_RUN and DOTFILES_REPO. Every step is idempotent: when there's nothing
# to remove it prints one skip line and changes nothing.

# Prints each symlink in the stow target dirs that points into the repo at a
# path that no longer exists. Stow links are relative, so targets are resolved
# from the link's own directory (readlink -m).
_find_dangling_repo_links() {
  local repo dir link target
  repo="$(realpath -m "$DOTFILES_REPO")"
  {
    # Unreadable dirs shouldn't abort a caller running with pipefail.
    find "$HOME" -maxdepth 1 -type l 2>/dev/null || true
    for dir in "$HOME/.config" "$HOME/.claude" "$HOME/.agents"; do
      if [ -d "$dir" ]; then
        find "$dir" -type l 2>/dev/null || true
      fi
    done
  } | while IFS= read -r link; do
    [ -e "$link" ] && continue
    target="$(readlink -m "$link")"
    if [[ "$target" == "$repo/"* ]]; then
      printf '%s\n' "$link"
    fi
  done
}

# Removes $1 and each parent that is left empty, stopping at $HOME.
_remove_empty_parents() {
  local dir="$1"
  while [ "$dir" != "$HOME" ] && [ "$dir" != "/" ] && [ -d "$dir" ] && [ -z "$(ls -A "$dir")" ]; do
    run "rmdir $(printf %q "$dir")"
    dir="$(dirname "$dir")"
  done
}

retire_dangling_stow_links() {
  local links link count=0 touched_agents=false
  links="$(_find_dangling_repo_links)"
  if [ -z "$links" ]; then
    print_skip "No dangling stow links"
    return
  fi

  while IFS= read -r link; do
    run "rm -f $(printf %q "$link")"
    count=$((count + 1))
    [[ "$link" == "$HOME/.agents/"* ]] && touched_agents=true
    if [ "$DRY_RUN" != true ]; then
      _remove_empty_parents "$(dirname "$link")"
    fi
  done <<<"$links"
  print_ok "Removed $count dangling stow links"

  # ~/.agents only held repo skills; anything left there came from another tool.
  if [ "$DRY_RUN" != true ] && [ "$touched_agents" = true ] && [ -e "$HOME/.agents" ]; then
    print_warn "~/.agents still has files that aren't from the repo — left in place"
  fi
}

retire_opendesign() {
  local dir="$HOME/.opendesign"
  local od_bin="$dir/node_modules/.bin/od"
  if [ ! -e "$dir" ]; then
    print_skip "OpenDesign is not installed"
    return
  fi
  if [ -x "$od_bin" ]; then
    run "$(printf %q "$od_bin") daemon stop || true"
  fi
  # Match the install path, never a bare "open-design", so nothing else is killed.
  # The bracketed first character stops pkill matching the `bash -c` that runs it.
  local pattern="[${dir:0:1}]${dir:1}/"
  if pgrep -f "$pattern" >/dev/null 2>&1; then
    # || true: the daemon may exit between pgrep and pkill, and pkill then exits 1
    run "pkill -f $(printf %q "$pattern") || true"
  fi
  run "rm -rf $(printf %q "$dir")"
  print_ok "OpenDesign removed"
}

retire_bun() {
  local dir="$HOME/.bun"
  if [ ! -e "$dir" ]; then
    print_skip "Bun is not installed"
    return
  fi
  run "rm -rf $(printf %q "$dir")"
  print_ok "Bun removed"
}

# superpowers is now an opencode plugin entry, so the old standalone clone goes.
retire_superpowers_clone() {
  local packages="$HOME/.local/share/opencode/packages"
  local clone="$packages/superpowers"
  if [ ! -e "$clone" ]; then
    print_skip "superpowers clone for opencode is not present"
    return
  fi
  run "rm -rf $(printf %q "$clone")"
  if [ "$DRY_RUN" != true ] && [ -z "$(ls -A "$packages")" ]; then
    run "rmdir $(printf %q "$packages")"
  fi
  print_ok "superpowers clone for opencode removed"
}

# Aspire is installed with its own script (~/.aspire/bin) on every machine, so a
# .NET global tool install is removed. Retire steps only remove: install.sh puts
# the script version back.
retire_aspire_dotnet_tool() {
  if ! command -v dotnet >/dev/null 2>&1 ||
     ! dotnet tool list -g 2>/dev/null | awk '{print $1}' | grep -qx 'aspire.cli'; then
    print_skip "Aspire is not installed as a .NET global tool"
    return
  fi
  run "dotnet tool uninstall -g aspire.cli"
  print_ok "Aspire .NET global tool removed — run ./install.sh to reinstall it with Aspire's install script"
}

run_retire_steps() {
  print_status "Retiring removed tools..."
  retire_dangling_stow_links
  retire_opendesign
  retire_bun
  retire_superpowers_clone
  retire_aspire_dotnet_tool
}

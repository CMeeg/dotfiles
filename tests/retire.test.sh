#!/usr/bin/env bash
set -euo pipefail

# Tests for lib/retire.sh. Each test runs in a throwaway HOME.
# Usage: bash tests/retire.test.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0
OUT=""

setup() {
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  export DOTFILES_REPO="$HOME/.dotfiles"
  mkdir -p "$DOTFILES_REPO"
  DRY_RUN=false

  print_status() { echo "• $1"; }
  print_ok()     { echo "✓ $1"; }
  print_skip()   { echo "- $1"; }
  print_warn()   { echo "! $1"; }
  print_dry()    { echo "~ $1"; }
  # Same contract as the real scripts: a failed command stops everything
  run() {
    if [ "$DRY_RUN" = true ]; then
      print_dry "$1"
      return 0
    fi
    bash -c "$1" || { echo "! Command failed: $1"; exit 1; }
  }

  # shellcheck source=../lib/retire.sh
  source "$REPO_ROOT/lib/retire.sh"
}

teardown() {
  rm -rf "${TMP:-}"
}

# Each test runs in its own subshell, so exit only ends that test.
fail() {
  echo "  $1"
  exit 1
}

# Runs a command, capturing its output in OUT.
capture() {
  OUT="$("$@" 2>&1)"
}

# Creates a relative link like stow does, pointing into the repo at a path that doesn't exist.
make_dangling_repo_link() {
  local link="$1" repo_rel="$2"
  mkdir -p "$(dirname "$link")"
  local rel
  rel="$(realpath -m --relative-to="$(dirname "$link")" "$DOTFILES_REPO/$repo_rel")"
  ln -s "$rel" "$link"
}

# ---------- retire_dangling_stow_links ----------

test_relative_dangling_repo_link_removed() {
  make_dangling_repo_link "$HOME/.agents/skills/x/SKILL.md" "agents/.agents/skills/x/SKILL.md"
  capture retire_dangling_stow_links
  [ ! -L "$HOME/.agents/skills/x/SKILL.md" ] || fail "link still present"
  [ ! -e "$HOME/.agents" ] || fail "~/.agents still present"
}

test_live_repo_link_kept() {
  mkdir -p "$DOTFILES_REPO/bash"
  echo "# bashrc" >"$DOTFILES_REPO/bash/.bashrc"
  ln -s ".dotfiles/bash/.bashrc" "$HOME/.bashrc"
  capture retire_dangling_stow_links
  [ -L "$HOME/.bashrc" ] || fail "live link removed"
}

test_dangling_link_outside_repo_kept() {
  mkdir -p "$HOME/.config"
  ln -s /nonexistent/foo "$HOME/.config/foo"
  capture retire_dangling_stow_links
  [ -L "$HOME/.config/foo" ] || fail "non-repo link removed"
}

test_empty_dirs_removed_but_not_home_or_config() {
  make_dangling_repo_link "$HOME/.config/a/b/c.toml" "pkg/.config/a/b/c.toml"
  echo keep >"$HOME/.config/keep.txt"
  capture retire_dangling_stow_links
  [ ! -e "$HOME/.config/a" ] || fail "~/.config/a still present"
  [ -d "$HOME/.config" ] || fail "~/.config removed"
  [ -d "$HOME" ] || fail "HOME removed"
}

test_agents_with_foreign_file_kept_and_warns() {
  make_dangling_repo_link "$HOME/.agents/skills/x/SKILL.md" "agents/.agents/skills/x/SKILL.md"
  mkdir -p "$HOME/.agents/skills/aspire"
  echo skill >"$HOME/.agents/skills/aspire/SKILL.md"
  capture retire_dangling_stow_links
  [ ! -L "$HOME/.agents/skills/x/SKILL.md" ] || fail "link still present"
  [ -f "$HOME/.agents/skills/aspire/SKILL.md" ] || fail "foreign file removed"
  [[ "$OUT" == *"left in place"* ]] || fail "no warning in output: $OUT"
}

test_dry_run_changes_nothing() {
  make_dangling_repo_link "$HOME/.agents/skills/x/SKILL.md" "agents/.agents/skills/x/SKILL.md"
  DRY_RUN=true
  capture retire_dangling_stow_links
  [ -L "$HOME/.agents/skills/x/SKILL.md" ] || fail "link removed in dry-run"
  [[ "$OUT" == *"~ "* ]] || fail "no dry-run line: $OUT"
  [[ "$OUT" == *"$HOME/.agents/skills/x/SKILL.md"* ]] || fail "link path not shown: $OUT"
}

test_second_run_is_noop() {
  make_dangling_repo_link "$HOME/.agents/skills/x/SKILL.md" "agents/.agents/skills/x/SKILL.md"
  capture retire_dangling_stow_links
  capture retire_dangling_stow_links
  [[ "$OUT" == *"- "* ]] || fail "no skip line: $OUT"
  [[ "$OUT" != *"✓"* ]] || fail "second run changed something: $OUT"
}

# ---------- retire_opendesign / retire_bun ----------

test_retire_opendesign_removes_dir() {
  mkdir -p "$HOME/.opendesign/node_modules"
  capture retire_opendesign
  [ ! -e "$HOME/.opendesign" ] || fail "~/.opendesign still present"
  [[ "$OUT" == *"✓"* ]] || fail "no ok line: $OUT"
}

test_retire_opendesign_skips_when_absent() {
  capture retire_opendesign
  [[ "$OUT" == *"- "* ]] || fail "no skip line: $OUT"
  [[ "$OUT" != *"✓"* ]] || fail "reported a change: $OUT"
}

# The daemon can exit between pgrep seeing it and pkill running; pkill then exits 1.
test_retire_opendesign_survives_process_exiting_before_pkill() {
  mkdir -p "$HOME/.opendesign" "$TMP/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$TMP/bin/pgrep"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/bin/pkill"
  chmod +x "$TMP/bin/pgrep" "$TMP/bin/pkill"
  export PATH="$TMP/bin:$PATH"
  capture retire_opendesign
  [ ! -e "$HOME/.opendesign" ] || fail "~/.opendesign still present: $OUT"
  [[ "$OUT" == *"✓"* ]] || fail "no ok line: $OUT"
}

test_retire_bun_removes_dir() {
  mkdir -p "$HOME/.bun/bin"
  capture retire_bun
  [ ! -e "$HOME/.bun" ] || fail "~/.bun still present"
}

test_retire_bun_dry_run_keeps_dir() {
  mkdir -p "$HOME/.bun/bin"
  DRY_RUN=true
  capture retire_bun
  [ -d "$HOME/.bun" ] || fail "~/.bun removed in dry-run"
  [[ "$OUT" == *"~ rm -rf"*".bun"* ]] || fail "no dry-run line: $OUT"
}

# ---------- retire_superpowers_clone ----------

test_retire_superpowers_clone_removes_dir_and_empty_packages() {
  mkdir -p "$HOME/.local/share/opencode/packages/superpowers/.git"
  capture retire_superpowers_clone
  [ ! -e "$HOME/.local/share/opencode/packages/superpowers" ] || fail "clone still present"
  [ ! -e "$HOME/.local/share/opencode/packages" ] || fail "empty packages dir still present"
  [ -d "$HOME/.local/share/opencode" ] || fail "~/.local/share/opencode removed"
}

test_retire_superpowers_clone_keeps_nonempty_packages() {
  mkdir -p "$HOME/.local/share/opencode/packages/superpowers/.git"
  mkdir -p "$HOME/.local/share/opencode/packages/other"
  capture retire_superpowers_clone
  [ ! -e "$HOME/.local/share/opencode/packages/superpowers" ] || fail "clone still present"
  [ -d "$HOME/.local/share/opencode/packages/other" ] || fail "other package removed"
}

# ---------- retire_aspire_dotnet_tool ----------

# Puts a fake `dotnet` first on PATH. It lists aspire.cli as a global tool when
# $1 is "installed", and logs every call to $TMP/dotnet.log.
fake_dotnet() {
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/dotnet" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$TMP/dotnet.log"
if [ "\$*" = "tool list -g" ]; then
  echo "Package Id      Version      Commands"
  echo "--------------------------------------"
  [ "$1" = installed ] && echo "aspire.cli      13.4.6       aspire"
fi
exit 0
EOF
  chmod +x "$TMP/bin/dotnet"
  export PATH="$TMP/bin:$PATH"
}

test_retire_aspire_dotnet_tool_uninstalls_global_tool() {
  fake_dotnet installed
  capture retire_aspire_dotnet_tool
  grep -qx "tool uninstall -g aspire.cli" "$TMP/dotnet.log" || fail "no uninstall call: $(cat "$TMP/dotnet.log")"
  [[ "$OUT" == *"✓"* ]] || fail "no ok line: $OUT"
}

test_retire_aspire_dotnet_tool_skips_when_not_a_global_tool() {
  fake_dotnet absent
  capture retire_aspire_dotnet_tool
  ! grep -q "uninstall" "$TMP/dotnet.log" || fail "uninstall called"
  [[ "$OUT" == *"- "* ]] || fail "no skip line: $OUT"
}

test_retire_aspire_dotnet_tool_skips_without_dotnet() {
  # A PATH with the basics but no dotnet (this machine has /usr/bin/dotnet)
  local tool
  mkdir -p "$TMP/sysbin"
  for tool in bash env grep awk cat ls rm; do
    ln -s "$(command -v "$tool")" "$TMP/sysbin/$tool"
  done
  PATH="$TMP/sysbin"
  capture retire_aspire_dotnet_tool
  [[ "$OUT" == *"- "* ]] || fail "no skip line: $OUT"
  [[ "$OUT" != *"✓"* ]] || fail "reported a change: $OUT"
}

test_retire_aspire_dotnet_tool_dry_run_does_not_uninstall() {
  fake_dotnet installed
  DRY_RUN=true
  capture retire_aspire_dotnet_tool
  ! grep -q "uninstall" "$TMP/dotnet.log" || fail "uninstall called in dry-run"
  [[ "$OUT" == *"~ dotnet tool uninstall -g aspire.cli"* ]] || fail "no dry-run line: $OUT"
}

# ---------- Runner ----------

main() {
  local tests name
  tests="$(declare -F | awk '{print $3}' | grep '^test_')"
  for name in $tests; do
    if (trap teardown EXIT; setup && "$name"); then
      echo "PASS $name"
    else
      echo "FAIL $name"
      FAILURES=$((FAILURES + 1))
    fi
  done
  [ "$FAILURES" -eq 0 ]
}

main "$@"

# Stage 0: Fix the Current Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tidy the existing bash + stow setup before the PowerShell migration: retire OpenDesign and Bun, install superpowers for opencode as a plugin, move shared skills into Claude's folder, clean up dangling stow links, restow `claude`, and make `update.sh` update GitKraken, fnm and Node.

**Architecture:** Retire steps live in a new sourced library `lib/retire.sh`, used by both `install.sh` and `update.sh` (they run it first, with a `--skip-retire` opt-out). GitKraken version helpers live in `lib/gitkraken.sh`. Both libraries rely on the calling script's existing `print_*` helpers, `run` and `DRY_RUN`, and are tested with plain bash test scripts against a temp `HOME`. Everything else is edits to the existing scripts, stow packages and docs.

**Tech Stack:** Bash, GNU Stow, curl, dpkg/apt, fnm.

**Spec:** `docs/superpowers/specs/2026-11-06-cross-platform-dotfiles-design.md`, section "Stage 0: fix the current setup".

## Global Constraints

- Edits inside `install.sh`/`update.sh` keep their 4-space indent and existing `print_status`/`print_ok`/`print_skip`/`print_warn`/`print_dry`/`run` helpers.
- New shell files use 2-space indent (AGENTS.md). Test scripts start with `#!/usr/bin/env bash` and `set -euo pipefail`. `lib/*.sh` files are sourced only: no shebang, no `set` options, no top-level side effects.
- `--dry-run` changes nothing on disk, in the repo or in running processes. Every destructive command goes through `run`.
- Retire steps are idempotent: when there's nothing to remove they print one `print_skip` line and change nothing.
- Scripts never commit or push. Each task ends with the user reviewing and committing.
- Markdown: no hard wrapping.
- opencode **stays**. GitKraken's settings stay manual (`gitkraken/README.md` unchanged).

## Review Focus

- **Stow links are relative** (e.g. `../.dotfiles/agents/.agents/skills/web-perf/SKILL.md` from inside `~/.agents/skills/web-perf/`). Dangling detection must resolve the target relative to the link's own directory. Owned by Task 1, `test_relative_dangling_repo_link_removed`.
- **No network for GitKraken's version lookup** (offline, slow or changed URL). Expected: one warning, the step is skipped, and `update.sh` carries on. Owned by Task 5, `test_version_from_url_rejects_unversioned_url` plus the `--max-time` on the lookup.
- **dpkg versions with a Debian revision** (`12.6.2-1`) must compare equal to the upstream `12.6.2`. Owned by Task 5, `test_needs_update_ignores_debian_revision`.
- **Other machines pull the Stage 0 commit with the old `update.sh`**, whose restow runs after the pull, so the new retire functions don't exist on that run. Expected: the docs say to `git pull` first, then run `./update.sh`; restow also runs the dangling-link cleanup after stowing. Owned by Task 4.
- **Something non-repo left under `~/.agents`** on another machine. Expected: kept, with one warning. Owned by Task 1, `test_agents_with_foreign_file_kept_and_warns`.

---

### Task 1: Retire library, dangling-link cleanup and wiring

**Files:**
- Create: `lib/retire.sh`, `tests/retire.test.sh` (executable)
- Modify: `install.sh` (arg parsing and help in `main`; call before `update_system`), `update.sh` (same)

**Interfaces:**
- Consumes (from the calling script): `print_status`, `print_ok`, `print_skip`, `print_warn`, `print_dry`, `run`, `DRY_RUN`, `DOTFILES_REPO`, `HOME`.
- Produces:
  - `retire_dangling_stow_links` — no args. Deletes every symlink found by `find "$HOME" -maxdepth 1 -type l` and `find <dir> -type l` for each of `~/.config`, `~/.claude`, `~/.agents` that exists, where the link's target (resolved relative to the link's directory, i.e. `readlink -m`) is under `$DOTFILES_REPO/` and doesn't exist. After deleting, removes now-empty parent directories, walking up but never removing `$HOME` itself. If `~/.agents` still exists afterwards, `print_warn "~/.agents still has files that aren't from the repo — left in place"`.
  - `run_retire_steps` — no args. Prints `print_status "Retiring removed tools..."` and calls each `retire_*` function in order. Tasks 2 and 3 add their functions to this list.
  - `SKIP_RETIRE` variable, default `false`, set by `--skip-retire` in both scripts.

- [x] **Step 1: Write the failing tests** in `tests/retire.test.sh`

  Harness: each test calls `setup`, which makes `TMP=$(mktemp -d)`, exports `HOME=$TMP/home` and `DOTFILES_REPO=$HOME/.dotfiles`, sets `DRY_RUN=false`, defines the five `print_*` functions as `echo "<prefix> $1"` (`•`, `✓`, `-`, `!`, `~`) and `run` as "if `DRY_RUN`, `print_dry`, else `bash -c "$1"`", then sources `$REPO_ROOT/lib/retire.sh`. The script runs every `test_*` function, prints `PASS <name>` / `FAIL <name>: <reason>`, and exits non-zero if any failed.

  | Test | Arrange | Assert |
  |---|---|---|
  | `test_relative_dangling_repo_link_removed` | `ln -s ../../.dotfiles/agents/.agents/skills/x/SKILL.md ~/.agents/skills/x/SKILL.md` (target missing) | link gone; `~/.agents` gone |
  | `test_live_repo_link_kept` | repo file `~/.dotfiles/bash/.bashrc` exists; `~/.bashrc` links to it | link still there |
  | `test_dangling_link_outside_repo_kept` | `~/.config/foo` → `/nonexistent/foo` | link still there |
  | `test_empty_dirs_removed_but_not_home_or_config` | dangling repo link at `~/.config/a/b/c.toml`; `~/.config/keep.txt` exists | `~/.config/a` gone; `~/.config` and `$HOME` still exist |
  | `test_agents_with_foreign_file_kept_and_warns` | dangling repo link `~/.agents/skills/x/SKILL.md` and a real file `~/.agents/skills/aspire/SKILL.md` | link gone; real file kept; output contains `left in place` |
  | `test_dry_run_changes_nothing` | dangling repo link as in the first test; `DRY_RUN=true` | link still there; output contains `~ ` and the link path |
  | `test_second_run_is_noop` | run cleanup twice on the first test's arrangement | second run's output contains `- ` and no `✓` |

- [x] **Step 2: Run the tests to verify they fail**

  Run: `bash tests/retire.test.sh`
  Expected: every test `FAIL` (`lib/retire.sh: No such file or directory`), non-zero exit.

- [x] **Step 3: Implement `retire_dangling_stow_links` and `run_retire_steps` in `lib/retire.sh`**

  Collect matching links first, then delete each with `run "rm -f $(printf %q "$link")"` and remove empty parents with `run "rmdir $(printf %q "$dir")"` while `$dir` is empty and not `$HOME`. In dry-run, print what would be removed and skip the parent-directory walk. Print `print_ok "Removed N dangling stow links"` or `print_skip "No dangling stow links"`.

- [x] **Step 4: Run the tests to verify they pass**

  Run: `bash tests/retire.test.sh`
  Expected: 7 × `PASS`, exit 0.

- [x] **Step 5: Wire into both scripts**

  In `install.sh` and `update.sh`: add `SKIP_RETIRE=false` next to `DRY_RUN`, parse `--skip-retire`, add it to the `--help` usage line (`Usage: $0 [--dry-run] [--skip-retire]`), `source "$DOTFILES_REPO/lib/retire.sh"` near the top, and in `main` call `run_retire_steps` (unless `SKIP_RETIRE` is true, in which case `print_skip "Skipping retire steps (--skip-retire)"`) right after the sudo keep-alive and before `update_system`.

- [x] **Step 6: Verify**

  ```bash
  bash -n install.sh && bash -n update.sh && echo SYNTAX_OK      # expect: SYNTAX_OK
  ./update.sh --dry-run | sed -n '1,15p'                         # expect: "Retiring removed tools..." block before "Updating system packages..."
  ./update.sh --dry-run --skip-retire | grep -c 'Skipping retire' # expect: 1
  ```

- [x] **Step 7: Checkpoint: user reviews and commits** (suggested: `add retire library with dangling stow link cleanup`)

---

### Task 2: Retire OpenDesign and Bun

**Files:**
- Modify: `lib/retire.sh`, `tests/retire.test.sh`, `install.sh` (`install_bun`, `install_opendesign` and their `main` calls), `update.sh` (`OPENDESIGN_DIR`, `update_bun`, `update_opendesign` and their `main` calls), `bash/.bashrc` (the `# bun` block, the `# opendesign` `od()` function and the auto-start block after it), `opencode/.config/opencode/opencode.jsonc` (the `open-design` MCP server), `linux/README.md` (the `## Bun` and `### OpenDesign` sections, and the "Update Bun" / "Update OpenDesign" items), `opencode/.config/opencode/README.md` (the `open-design` mention in the verify list)
- Delete: `opendesign/` (only contains `README.md`)

**Interfaces:**
- Consumes: Task 1's harness and `run_retire_steps`.
- Produces: `retire_opendesign` and `retire_bun`, added to `run_retire_steps` in that order.

- [x] **Step 1: Write the failing tests**

  | Test | Arrange | Assert |
  |---|---|---|
  | `test_retire_opendesign_removes_dir` | `mkdir -p ~/.opendesign/node_modules` | `~/.opendesign` gone; output contains `✓` |
  | `test_retire_opendesign_skips_when_absent` | nothing | output contains `- ` and no `✓` |
  | `test_retire_bun_removes_dir` | `mkdir -p ~/.bun/bin` | `~/.bun` gone |
  | `test_retire_bun_dry_run_keeps_dir` | `mkdir -p ~/.bun/bin`; `DRY_RUN=true` | `~/.bun` still there |

- [x] **Step 2: Run the tests to verify they fail**

  Run: `bash tests/retire.test.sh`
  Expected: the 4 new tests `FAIL` (`retire_opendesign: command not found` etc.), Task 1's tests still `PASS`.

- [x] **Step 3: Implement `retire_opendesign` and `retire_bun`**

  `retire_opendesign`: skip if `~/.opendesign` doesn't exist. Otherwise, if `~/.opendesign/node_modules/.bin/od` is executable, `run` `"<that path> daemon stop || true"`; then, if `pgrep -f "$HOME/.opendesign/"` finds anything, `run "pkill -f '$HOME/.opendesign/'"` (match the install path, never a bare `open-design`, so tests and other processes are safe); then `run "rm -rf ~/.opendesign"`. `retire_bun`: skip if `~/.bun` doesn't exist; else `run "rm -rf ~/.bun"`.

- [x] **Step 4: Run the tests to verify they pass**

  Run: `bash tests/retire.test.sh`
  Expected: 11 × `PASS`, exit 0.

- [x] **Step 5: Remove OpenDesign and Bun from scripts, config and docs** (the files listed above)

- [x] **Step 6: Verify**

  ```bash
  bash -n install.sh && bash -n update.sh && bash -n bash/.bashrc && echo SYNTAX_OK
  grep -rn -i -E 'opendesign|open-design|\bbun\b' --exclude-dir=.git --exclude-dir=docs . # expect: only lib/retire.sh and tests/retire.test.sh
  ./update.sh --dry-run | grep -E 'OpenDesign|Bun'          # expect: only the two retire lines ("~ … rm -rf …")
  python3 -c 'import json,re,sys; json.loads(re.sub(r"^\s*//.*$","",open(sys.argv[1]).read(),flags=re.M))' opencode/.config/opencode/opencode.jsonc && echo JSON_OK
  ```

- [x] **Step 7: Checkpoint: user reviews and commits** (suggested: `retire OpenDesign and Bun`)

---

### Task 3: superpowers for opencode as a plugin

**Files:**
- Modify: `opencode/.config/opencode/opencode.jsonc` (`plugins` entry), `install.sh` (delete `install_superpowers` and its `main` call; `is_repo_behind` stays only if still used), `update.sh` (delete `SUPERPOWERS_DIR`, `update_superpowers` and its `main` call), `lib/retire.sh`, `tests/retire.test.sh`, `linux/README.md` (the "Add Superpowers" clone steps and "Update Superpowers"), `opencode/.config/opencode/README.md` (migration step 2, the `~/.agents/skills` verify line, and the "Git spec plugin install silently fails (V1)" section)

**Interfaces:**
- Consumes: Task 1's harness and `run_retire_steps`.
- Produces: `retire_superpowers_clone`, added to `run_retire_steps` after `retire_bun`.

- [x] **Step 1: Write the failing tests**

  | Test | Arrange | Assert |
  |---|---|---|
  | `test_retire_superpowers_clone_removes_dir_and_empty_packages` | `mkdir -p ~/.local/share/opencode/packages/superpowers/.git` | `superpowers` gone; `packages` gone (empty); `~/.local/share/opencode` still exists |
  | `test_retire_superpowers_clone_keeps_nonempty_packages` | as above plus `~/.local/share/opencode/packages/other/` | `superpowers` gone; `packages/other` still exists |

- [x] **Step 2: Run the tests to verify they fail**

  Run: `bash tests/retire.test.sh`
  Expected: the 2 new tests `FAIL`, the rest `PASS`.

- [x] **Step 3: Implement `retire_superpowers_clone`**

  Skip if `~/.local/share/opencode/packages/superpowers` doesn't exist; else `run "rm -rf …/superpowers"`, then `run "rmdir …/packages"` only if it's empty.

- [x] **Step 4: Run the tests to verify they pass**

  Run: `bash tests/retire.test.sh`
  Expected: 13 × `PASS`, exit 0.

- [x] **Step 5: Switch the config and remove the clone steps**

  `opencode.jsonc`: `"plugins": ["superpowers@git+https://github.com/obra/superpowers.git"]`. In the opencode README, replace the clone-based instructions with the plugin entry, keep the V1 known-issue section but note it only applied to OpenCode 1.17.7 and that v2 (2.0.4+) installs git specs, and add: "If a superpowers update doesn't appear, clear opencode's package cache or reinstall the plugin" (from superpowers' install notes).

- [x] **Step 6: Verify (user, in opencode)**

  After `stow --adopt --no-folding -v opencode` and restarting opencode, ask it "Tell me about your superpowers".
  Expected: it lists superpowers skills. If it doesn't load on opencode 2.2.5, stop and report back: the fallback is reverting this task and keeping the clone.

- [x] **Step 7: Checkpoint: user reviews and commits** (suggested: `install superpowers for opencode as a plugin`)

---

### Task 4: Move shared skills to Claude's folder and restow `claude`

**Files:**
- Move: `agents/.agents/skills/*` → `claude/.claude/skills/` (`git mv`, six skill folders)
- Delete: `agents/` (including its `.stow-local-ignore`)
- Modify: `install.sh` (`stow_opencode_dotfiles`: package list and the `find-docs` `is_symlinked` check), `update.sh` (`restow`: package list becomes `bash git opencode starship superfile herdr claude`; call `retire_dangling_stow_links` after a successful stow), `AGENTS.md` (Key Commands rows, stow package list), `linux/README.md` (stow commands at the opencode section and in "Restow"; add "on other machines, `git pull` first, then `./update.sh`" to the update section), `claude/README.md` (skills section: skills here are also read by opencode), `opencode/.config/opencode/README.md` (stow command in migration step 4)

**Interfaces:**
- Consumes: `retire_dangling_stow_links` (Task 1).
- Produces: nothing new.

- [x] **Step 1: Move the skills and update scripts and docs** (files above). `stow_opencode_dotfiles` stows only `opencode` and checks `opencode.jsonc`; skills now arrive with `stow_claude_dotfiles`.

- [x] **Step 2: Restow this machine**

  Run: `stow --no-folding -v -R claude opencode`
  The old `~/.agents` links now dangle; Task 7's real `./update.sh` run removes them and `~/.agents`.

- [x] **Step 3: Verify**

  ```bash
  ls -l ~/.claude/skills/find-docs/SKILL.md            # expect: symlink into ~/.dotfiles/claude/.claude/skills/
  find ~ -maxdepth 1 -xtype l; find ~/.config ~/.claude -xtype l   # expect: no output (only ~/.agents has dangling links)
  grep -rn 'agents/\.agents\|stow .*agents' --exclude-dir=.git --exclude-dir=docs .   # expect: no output
  ```
  Then (user): Claude Code's `/skills` and opencode both list `find-docs`, `web-perf` and the other four.

- [x] **Step 4: Checkpoint: user reviews and commits** (suggested: `share skills between Claude Code and opencode; restow claude on update`)

---

### Task 5: GitKraken updates

**Files:**
- Create: `lib/gitkraken.sh`, `tests/gitkraken.test.sh` (executable)
- Modify: `update.sh` (source the library; add `update_gitkraken` and call it after `update_system`), `install.sh` (source the library; `install_gitkraken` uses `GITKRAKEN_DEB_URL`), `linux/README.md` (add "Update GitKraken" to the update section)

**Interfaces:**
- Produces, in `lib/gitkraken.sh`:
  - `GITKRAKEN_DEB_URL="https://release.gitkraken.com/linux/gitkraken-amd64.deb"`
  - `gitkraken_version_from_url <url>` → echoes the version from a path segment matching `/linux/x64/<digits(.digits)+>/`, returns 1 if none.
  - `gitkraken_latest_version` → `curl -fsSL --max-time 20 -r 0-0 -o /dev/null -w '%{url_effective}' "$GITKRAKEN_DEB_URL"`, piped through `gitkraken_version_from_url`; returns 1 on any failure.
  - `gitkraken_needs_update <installed> <latest>` → returns 0 when they differ after stripping a Debian revision (`${installed%%-*}`), 1 when equal.

- [x] **Step 1: Write the failing tests** in `tests/gitkraken.test.sh` (same PASS/FAIL harness style as Task 1; source `lib/gitkraken.sh` only, no network)

  | Test | Assert |
  |---|---|
  | `test_version_from_url_parses_redirect` | `gitkraken_version_from_url "https://release.gitkraken.dev/gkd/production/normal/linux/x64/12.6.2/3LdymkbiGLlvUgLoGwehfDP0Qeo/gitkraken-amd64.deb"` echoes `12.6.2` |
  | `test_version_from_url_rejects_unversioned_url` | `gitkraken_version_from_url "https://release.gitkraken.com/linux/gitkraken-amd64.deb"` returns 1, echoes nothing |
  | `test_needs_update_when_versions_differ` | `gitkraken_needs_update 12.6.2 12.7.0` returns 0 |
  | `test_needs_update_false_when_equal` | `gitkraken_needs_update 12.6.2 12.6.2` returns 1 |
  | `test_needs_update_ignores_debian_revision` | `gitkraken_needs_update 12.6.2-1 12.6.2` returns 1 |

- [x] **Step 2: Run the tests to verify they fail**

  Run: `bash tests/gitkraken.test.sh`
  Expected: every test `FAIL`, non-zero exit.

- [x] **Step 3: Implement `lib/gitkraken.sh`**

- [x] **Step 4: Run the tests to verify they pass**

  Run: `bash tests/gitkraken.test.sh`
  Expected: 5 × `PASS`, exit 0.

- [x] **Step 5: Add `update_gitkraken` to `update.sh`**

  Skip if `! is_apt_installed gitkraken` (copy `is_apt_installed` from `install.sh`). Look up the latest version even in dry-run (read-only, one small request); on failure `print_warn "Couldn't work out the latest GitKraken version — skipping"` and return. If `gitkraken_needs_update` says no, `print_skip "GitKraken is already up to date (<version>)"`. Otherwise `run` the same `wget -O /tmp/gitkraken-amd64.deb … && sudo apt install -y /tmp/gitkraken-amd64.deb` as `install_gitkraken`, and `print_ok "GitKraken updated to <version>"`.

- [x] **Step 6: Verify**

  ```bash
  bash -n update.sh && bash -n install.sh && echo SYNTAX_OK
  bash -c 'source lib/gitkraken.sh; gitkraken_latest_version'   # expect: a version like 12.6.2
  ./update.sh --dry-run | grep -A2 'Updating GitKraken'          # expect: "already up to date (12.6.2)" or a "~ wget …" line
  ```

- [x] **Step 7: Checkpoint: user reviews and commits** (suggested: `update GitKraken from its latest .deb`)

---

### Task 6: fnm and Node LTS updates

**Files:**
- Modify: `install.sh` (`NODE_VERSION` removed; `install_node`), `update.sh` (add `update_node`, called after `update_gitkraken`), `linux/README.md` (Node section and an "Update fnm and Node" item)

**Interfaces:**
- Produces, defined once in `install.sh` and `update.sh` (each script keeps its own copy, as with the other helpers): `latest_node_lts` → echoes the newest LTS version from `fnm list-remote --lts | tail -n1 | awk '{print $1}'` (e.g. `v26.13.0`); returns 1 if empty.

- [x] **Step 1: Change `install_node`**

  Install fnm with `curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell` (`bash/.bashrc` already sets up fnm, so the installer must not append to it). Then `fnm install <latest_node_lts>` and `fnm default <same>`. Keep the existing PATH export block.

- [x] **Step 2: Add `update_node`**

  Skip if `! is_cmd fnm`. Re-run the fnm installer with `--skip-shell` (updates the binary; fnm has no self-update command). Then get `latest_node_lts`; if it fails, `print_warn` and return. If `fnm list` already contains it and `fnm current` equals it, `print_skip "Node <version> (latest LTS) is already the default"`. Otherwise `run "fnm install <v> && fnm default <v>"` and `print_ok`. Old Node versions are left installed. The `fnm list-remote` lookup runs in dry-run too (read-only), as GitKraken's does.

- [x] **Step 3: Verify**

  ```bash
  bash -n install.sh && bash -n update.sh && echo SYNTAX_OK
  ./install.sh --dry-run | grep -A3 'fnm'      # expect: "fnm is already installed" skip
  ./update.sh --dry-run | grep -A4 'Updating fnm'   # expect: installer line with --skip-shell, fnm install/default lines
  ```

- [x] **Step 4: Checkpoint: user reviews and commits** (suggested: `keep fnm and Node LTS up to date`)

---

### Task 7: Real run on this machine

**Files:** none (verification only; fix anything it turns up in the owning task's files).

- [x] **Step 1: Run the tests**

  ```bash
  bash tests/retire.test.sh && bash tests/gitkraken.test.sh   # expect: all PASS
  ```

- [x] **Step 2: Run `./update.sh` for real** (the user runs it, since it needs `sudo` and restarts tools)

  Expected: the retire block removes `~/.opendesign` (after stopping its daemon), `~/.bun`, the superpowers clone, and the dangling `~/.agents` links along with `~/.agents` itself; GitKraken reports up to date or updates; fnm is reinstalled in place and Node's latest LTS becomes the default; restow includes `claude`.

- [x] **Step 3: Verify**

  ```bash
  test ! -e ~/.opendesign && test ! -e ~/.bun && test ! -e ~/.local/share/opencode/packages/superpowers && echo RETIRED
  node -v && fnm current                    # expect: the latest LTS from `fnm list-remote --lts`, both the same
  test ! -e ~/.agents && echo AGENTS_GONE  # expect: AGENTS_GONE
  ./update.sh --dry-run | sed -n '/Retiring/,/Updating system/p'   # expect: only "-" skip lines in the retire block
  git status --short                        # expect: no changes from stow --adopt (or review them)
  ```

- [x] **Step 4: Checkpoint: user reviews and commits any fixes**

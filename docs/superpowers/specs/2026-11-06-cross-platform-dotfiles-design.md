# Cross-platform dotfiles and tool management — design

Date: 2026-11-06. Replaces the stow → chezmoi plan in `docs/superpowers/plans/2026-10-27-chezmoi-migration.md`, which is no longer being pursued.

## Why

The repo manages dotfiles for Debian on WSL with GNU Stow, plus bash `install.sh` and `update.sh` scripts. The scripts work well. Two things don't:

1. **Tools inject machine-specific settings into managed files.** GitKraken adds a marketplace entry with an absolute path to `~/.claude/settings.json` on its own. herdr adds a SessionStart hook with an absolute path when you register its Claude integration through its CLI or TUI. Because stow makes the live file and the repo file the same file, these entries show up in every `git diff` and have to be remembered and left out of commits. Home paths differ between machines (`/home/meeg`, `/home/chrism`, `C:\Users\cpmee`), so the entries aren't portable. Rewriting them by hand (e.g. `$HOME` in the herdr hook) stops the tool from recognising its own entry, which led to duplicate herdr hooks. This needs to be solved as a general problem, not just for these two tools.
2. **Windows setup isn't automated at all.** `windows/README.md` is a set of manual copy steps, and stow isn't available on Windows. Windows machines should eventually get the same or similar tools and config, set up and updated the way Linux is.

## Goals

- The repo holds the **intended** settings, written once where possible, as plain config files that read like the real thing (no tool-specific naming like `dot_` or `modify_`).
- Setup writes **real files** to each machine (never symlinks), so tools writing to them never touch the repo.
- **Two-way sync:** repo changes are applied to live files without overwriting machine-local changes; local changes can be contributed back to the repo in a semi-automated way.
- **Portable paths:** the home path is stored as a placeholder in the repo and filled in per machine.
- **One set of PowerShell 7 scripts** (`install.ps1`, `update.ps1`, `sync.ps1`, `retire.ps1`) for Linux and, later, Windows. A tiny per-OS bootstrap gets `pwsh` installed first.
- **Retiring tools converges every machine:** when a tool is dropped from the repo, a long-lived removal step uninstalls it and cleans up its files on any machine that still has it.
- Keep what works today: idempotent scripts, dry-run support, the same output style, scripts never commit or push.

## Non-goals

- Adopting chezmoi, dotter, dotdrop or similar. They were researched; chezmoi was closest, but its features depend on its own source naming, and copy-back would still have needed custom code. The user prefers plain files and owning a small amount of code.
- A key-by-key JSON merge engine. Merging is line-based with `git merge-file` (see below).
- OS-specific overrides inside config files. YAGNI for now. If they're ever needed, the user prefers seeing differences inline in one file over separate per-OS override files.
- Avoiding the noise from local-only entries in the sync report (see Parked ideas). The user edits these files rarely and will live with it at first.
- Secrets management. `~/.secrets` stays a gitignored, unmanaged file.

## Anti-goals

- **Near-duplicate per-OS copies of the same config file.** This is why a separate Windows `settings.json` was rejected.
- Making it easy to commit machine-specific values by accident.
- Magic: behaviour hidden in naming conventions or a database you can't inspect.

## Staging

The work happens in stages. Stages 0 and 1 are designed in detail here.

0. **Stage 0: fix the current setup.** Changes to today's bash scripts, stow packages and docs, before any migration. See "Stage 0" below.
1. **Stage 1: sync engine and Linux port.** Build `sync.ps1` and `retire.ps1`, port `install.sh` and `update.sh` to PowerShell 7, retire stow (moving existing Linux machines over), and port Stage 0's retire steps into `retire.ps1`. Linux must be fully tested and correct before Stage 3 starts.
2. **Stage 2: document the Windows setup.** Flesh out `windows/README.md` so every manual step is written down, probably through a guided exploration session with Claude Code on the Windows machine. This is the input for Stage 3.
3. **Stage 3: Windows additions.** Add Windows steps to the same scripts (winget instead of apt; custom installers; setup actions), Windows targets in the manifest, and the Windows forms of the home placeholder. Also explore a script for removing Chocolatey and its packages so they can be reinstalled with winget (the user wants to see what that script would look like before choosing script vs manual). This stage gets its own design pass after Stage 2. Herdr app inputs for it (manual steps already in `windows/README.md`): installing the app; the WSL SSH key and the `Host debian-wsl` SSH config entry (named `<distro>-wsl`, since herdr names the machine after it; `HostName 127.0.0.1`, not `localhost`); the app's own config in `%USERPROFILE%\.config\herdr-app` (settings, keys, layouts, programs) as manifest entries; and how the Windows public key gets into WSL's `authorized_keys`. That last one crosses environments, which the "separate clones per environment" decision rules out, so it needs its own design call. Before that call, ask the herdr project whether `--via` is meant to work in the Windows herdr-core: on 2026-11-09 it rejected every `--via` command (see the Herdr app decision), and quoting or a missing `sh` isn't the cause, as `-e sh -c`, plain `wsl.exe` and Git for Windows' `sh` on `PATH` all got the same error. If it worked, `--via "wsl.exe -d <distro>"` would remove sshd, port 2222 (one distro per PC), the key, the SSH config entry and this `authorized_keys` step. Also from `windows/README.md` and `claude/README.md`: `jq` via winget, and `claude/.claude/CLAUDE.md` (copied by hand today) as a `windows` key on its manifest entry.

## Decisions (made by the user)

- Repo holds intended settings; live files are real copies; machine-local entries live only on the machine.
- Sync is two-way, with semi-automated copy-back that turns machine paths back into placeholders.
- Plain config files in the repo; own scripts instead of an existing dotfiles tool.
- PowerShell 7 for one set of scripts covering both OSes, started by a bootstrap that installs `pwsh`.
- **Separate clones per environment.** Each Windows install, each WSL distro and each plain Linux machine has its own clone of the repo and its own state. Nothing reaches across `\\wsl$`. Some machines won't use WSL; some may have several distros.
- `sync` shows a diff and leans on git and a three-way merge tool.
- Local-only noise in the sync report is accepted for now; ideas for fixing it are documented under Parked ideas.
- Tools are installed by steps written in script code, as in `install.sh` today: a package-manager install (apt, later winget) or a custom installer, optionally followed by setup commands (e.g. registering herdr's Claude integration).
- Standardise on winget for Windows (Stage 3).
- **Removing a tool** means taking it out of the install/update scripts, the manifest and the repo, and adding a removal step to a long-lived script (`retire.ps1`) that uninstalls it and deletes its leftovers if present. `install.ps1` and `update.ps1` both run it **automatically**, each with an opt-out switch. The move off stow is the first such step rather than a separate throwaway script.
- **Retired tools (confirmed):** OpenDesign and Bun, plus the superpowers clone and the `agents` stow package, which are replaced rather than dropped (see Stage 0). opencode **stays**. All of these happen in Stage 0; Stage 1 only adds the stow retirement.
- **GitKraken's settings stay manual.** Editing its profile file would be an unofficial workaround, so it was rejected.
- **Directory entries manage the whole folder** (e.g. all of a skills folder), so files that other tools add there show up as new local files until excluded in the manifest. Since 2026-11-08 no Stage 1 entry uses this (`claude/.claude/skills` and `opencode/.config/opencode/commands` were removed from the repo), but the user chose to keep directory entries in Stage 1, covered by the sync tests, for folders added later.
- **Skills live in local plugins** (2026-11-08; supersedes Stage 0 step 4's `claude/.claude/skills`). All skills are in `claude/.claude/local-plugins/<plugin>/skills/`, which Claude Code loads from the repo via `CLAUDE_CODE_PLUGIN_DIRS` and opencode via the `skills` list in `opencode.jsonc`. Neither copies them into home, so they aren't in the manifest.
- Stage order as above.
- **Herdr desktop app alongside the TUI** (2026-11-08). The Windows Herdr app manages agents in WSL by connecting to the distro over SSH (sshd on `127.0.0.1:2222`, key login only). This was tested by hand and works: agent status, notifications, and reconnecting after `wsl --shutdown`. sshd was chosen over herdr-core's `--via wsl.exe` option. Tested on 2026-11-09, the Windows herdr-core (0.1.19) rejects every `--via` command, even the example from its own help, with `bad command "…": one line, run by sh here`, while the Linux build accepts the same command, so SSH is the only way to connect for now. The herdr TUI and its Claude/opencode integrations **stay** for now; retiring the TUI is a later decision. Until each stage automates them, the steps are written down as manual steps in `linux/README.md` and `windows/README.md`.

## Stage 0: fix the current setup

Done in the existing bash scripts (`install.sh`, `update.sh`, 4-space indent, existing `print_*`/`run` helpers) and stow packages, so the Stage 1 port starts from a clean baseline. Each change is a separate, reviewable step.

1. **Retire OpenDesign.** Remove `install_opendesign`/`update_opendesign`, the `opendesign/` folder and every doc mention. Add a retire step (below) that stops its daemon if running and deletes `~/.opendesign`.
2. **Retire Bun.** Bun was only needed for OpenDesign. Remove `install_bun`/`update_bun` and the Bun lines in `bash/.bashrc`. The retire step deletes `~/.bun`.
3. **superpowers for opencode as a plugin.** Replace the clone with superpowers' own opencode v2 install method: a `plugins` entry `superpowers@git+https://github.com/obra/superpowers.git` in `opencode/.config/opencode/opencode.jsonc` (replacing the current local-path entry). Delete `install_superpowers`/`update_superpowers` and their `opencode.jsonc` patching. The retire step deletes the old clone at `~/.local/share/opencode/packages/superpowers`. Document in `opencode/.config/opencode/README.md` that a stale plugin can need opencode's package cache cleared (per superpowers' install notes).
4. **Shared skills move to Claude's folder.** opencode reads `~/.claude/skills` as well as `~/.agents/skills`; Claude Code reads only `~/.claude/skills`. Move the six skills from `agents/.agents/skills/` to `claude/.claude/skills/` (with `git mv`, so history follows; `.gitignore` already allowlists `claude/.claude/skills/`), and delete the `agents` package from `install.sh`, `update.sh`, `AGENTS.md` and the READMEs. The user has already deleted the non-repo skills (Aspire's, `find-skills`) and `.skill-lock.json` from this machine, so after Stage 0 `~/.agents` holds nothing and is removed (step 5). *Superseded on 2026-11-08: the skills moved again, into local plugins (see Decisions).*
5. **Clean up dangling stow links.** Moving or deleting packages leaves links in `$HOME` pointing at paths that no longer exist in the repo. A retire step deletes every symlink under `$HOME` (top level, `~/.config`, `~/.claude`, `~/.agents`) that points into `~/.dotfiles` and is dangling, then removes directories left empty by that, including `~/.agents/skills` and `~/.agents` themselves. If anything that isn't a repo link remains under `~/.agents` (e.g. another tool's skill on a different machine), it's left in place with a warning rather than deleted. Links that still resolve are untouched.
6. **Restow includes `claude`.** `update.sh`'s package list omits `claude` (an oversight from commit `663cf76`). Add it, and fix the matching command in `linux/README.md`.
7. **GitKraken updates.** The `.deb` adds no apt repo, so `apt upgrade` never updates it. Add `update_gitkraken`: request `https://release.gitkraken.com/linux/gitkraken-amd64.deb` without downloading it, read the version from the redirect location (`…/linux/x64/<version>/…/gitkraken-amd64.deb`), and compare it with `dpkg-query -W -f='${Version}' gitkraken`. If they differ, download and `sudo apt install` the `.deb` as `install_gitkraken` does. If the redirect doesn't contain a recognisable version (the URL format is not a documented API), warn and skip rather than fail. Skip if GitKraken isn't installed.
8. **fnm and Node updates.** Add `update_node`: re-run fnm's install script with `--skip-shell` (updates the binary without touching `.bashrc`; fnm has no self-update command), then `fnm install --lts` and `fnm default <installed LTS version>`. Old Node versions are left installed. In `install.sh`, install the latest LTS instead of the pinned `NODE_VERSION="24"` and set it as the default, so install and update agree.

**Retire steps in bash.** Steps 1, 2, 3 and 5 add idempotent `retire_*` functions (skip with a `-` line when there's nothing to remove; respect `--dry-run`). `update.sh` runs them first, and `install.sh` runs them first too, both with an opt-out flag (e.g. `--skip-retire`). Stage 1 ports these functions into `retire.ps1` unchanged in behaviour.

**Docs.** Update `AGENTS.md`, `linux/README.md`, `opencode/.config/opencode/README.md` and `claude/README.md` for each change. `gitkraken/README.md` keeps its manual setup steps.

**Verify.** `bash -n` on both scripts; `--dry-run` of each lists the new and removed steps; on this machine, a real `update.sh` run retires OpenDesign, Bun and the superpowers clone, removes dangling links and `~/.agents`, and both Claude Code and opencode list the moved skills.

## Stage 1 design

### Repo layout

Builder's choice within these rules, but the default is to **keep the current directory layout** (`bash/.bashrc`, `claude/.claude/settings.json`, `starship/.config/starship.toml`, …). It keeps git history, keeps existing stow links valid while a machine migrates, and the manifest no longer cares how files are laid out. (My call; see "Calls made during design" at the end.)

Removed in Stage 1: every `.stow-local-ignore` file. (`agents/` and `opendesign/` are already gone after Stage 0.) The manifest replaces them.

New at the repo root:

- `dotfiles.json`: the manifest.
- `bootstrap.sh`: Linux bootstrap.
- `install.ps1`, `update.ps1`, `sync.ps1`, `retire.ps1`: the scripts. Shared helpers can go in a module (e.g. `lib/Dotfiles.psm1`).
- `tests/`: Pester tests.

`install.sh` and `update.sh` are deleted at the end of Stage 1, once the PowerShell versions are verified. Git history keeps them.

### Manifest (`dotfiles.json`)

Lists every managed entry with its target per OS. Modelled on drmohundro/dotfiles' `overrides.json` (an OS-keyed map, `~` and `%VAR%` expanded with `[Environment]::ExpandEnvironmentVariables`), but explicit: nothing is managed unless it's listed.

Each entry is either a **file** or a **directory**. For a directory, every file under it is managed, minus any `exclude` globs. Example shape (the builder may refine it):

```json
{
  "entries": [
    { "source": "bash/.bashrc",                  "linux": "~/.bashrc" },
    { "source": "starship/.config/starship.toml", "linux": "~/.config/starship.toml" },
    { "source": "claude/.claude/settings.json",  "linux": "~/.claude/settings.json" },
    { "source": "claude/.claude/CLAUDE.md",      "linux": "~/.claude/CLAUDE.md" },
    { "source": "example/skills",                "linux": "~/.example/skills", "exclude": ["synced/**"] }
  ]
}
```

An entry with no key for the current OS is skipped on that OS. Stage 3 adds `windows` keys. The scripts also read a `macos` key on macOS (name *provisional*, 2026-11-08): no stage targets macOS, but it leaves room for it later. Stage 1 must manage the set stow manages today minus the retired packages: every file in `bash`, `git`, `starship`, `superfile`, `herdr` and `claude`, minus `.stow-local-ignore` and `README.md`, with `.gitignore` rules still applying. Directory entries manage the whole folder on the target side, so files there that aren't in the repo are reported as new local files until excluded. (`example/skills` above only shows the shape: no Stage 1 entry is a directory.) `claude/.claude/local-plugins` is loaded straight from the repo (Claude Code via `CLAUDE_CODE_PLUGIN_DIRS`, opencode via the `skills` list in `opencode.jsonc`) and doesn't need copying.

### Home-path placeholder

- The repo stores `@HOME@` wherever a file needs the machine's home path.
- **Apply:** every managed text file has `@HOME@` replaced with the machine's home path before it's compared or written.
- **Copy-back:** the machine's home path is replaced with `@HOME@` before the content goes into the repo.
- Stage 1 handles the Linux form (`/home/<user>`). Stage 3 adds the Windows forms (`C:\Users\<user>`, and the JSON-escaped `C:\\Users\\<user>`).
- Files without a placeholder are unaffected. A literal `~` stays as written.
- **`@DOTFILES@`** (decided 2026-11-08, after Stage 1's final review) stands for the clone's own path, for config that points into the repo (Claude Code's `CLAUDE_CODE_PLUGIN_DIRS`, opencode's `skills` list), so the local plugins load from a clone anywhere. Apply fills it in with the repo folder sync is using; copy-back turns that path back into `@DOTFILES@` before turning the home path into `@HOME@`, since the clone is usually under home. The same boundary rule applies: the path must be followed by `/`, a quote, whitespace, `:` or the end of the text.

### State

Each environment keeps a **last-applied copy** of every managed file: exactly what sync last wrote (placeholders filled in). It's a plain folder mirroring target paths, e.g. `~/.local/state/dotfiles/applied/` on Linux. It's not a database: you can `diff` against it, and deleting it resets the machine's tracking. Stage 3 picks the Windows location (e.g. under `%LOCALAPPDATA%`).

### `sync.ps1`

Usage: `sync.ps1 [-NoPull] [-WhatIf]`, reading `DOTFILES_REPO` (default `~/.dotfiles`).

1. **Pull** (skipped with `-NoPull`). Stash a dirty repo, `git pull --rebase`, pop the stash, as `update.sh`'s `restow` does today (its plain `git pull` already rebases via `pull.rebase = true` in the repo's `.gitconfig`; the flag makes that explicit). If the pull or the stash pop leaves a git conflict, report the unmerged files and stop before touching any live file (non-zero exit).
2. **Apply**, for each managed file, using `repo` = the repo **working-tree** version with the placeholder filled in (so uncommitted repo edits can be tried out with a sync), `base` = last-applied copy, and `live` = the file on disk:

   | Situation | Action |
   |---|---|
   | live missing, no base | write repo |
   | live == repo, no base | nothing to write; record repo as last applied |
   | live == repo, base exists | nothing to write; record repo as last applied **only if the repo file has no uncommitted changes**, otherwise **don't** touch the last-applied copy |
   | live == base (only repo changed) | write repo |
   | repo == base (only live changed) | leave live alone; list as a local change |
   | both changed | `git merge-file` live ← base → repo. Clean merge (and, for `.json`/`.jsonc`, still parses with `ConvertFrom-Json` and has no key twice in one object) → write it. The duplicate-key check was added on 2026-11-08: `ConvertFrom-Json` accepts duplicate keys, and both sides adding the same key in different places is the usual way a clean textual merge breaks a JSON file (a missing comma needs adjacent edits, which `git merge-file` already reports as a conflict). Otherwise it's a conflict (below). |
   | no base, live differs from repo | conflict (first sight of an unmanaged-by-sync file) |
   | live missing, base exists | deleted locally; report it, don't recreate it |
   | file removed from repo, live == base | delete live |
   | file removed from repo, live changed | report it, leave live alone |

   **The last-applied copy changes only when sync writes the repo version (or a merge result) to the live file**, plus the first-sight case above. Copy-back never updates it, and neither does live happening to equal repo. This guards local-only entries: if copy-back puts a local-only entry (e.g. GitKraken's) into the repo working tree and a sync runs before the user discards it, the base still lacks it. After the user discards it, repo == base again and live is just "changed locally", so the entry survives instead of looking like something the repo deleted. A Pester test must cover exactly this sequence.

   **Updated 2026-11-08** (supersedes "neither does live happening to equal repo" above, found in the Stage 1 review): when live equals repo and the repo file has no uncommitted changes (`git status --porcelain -- <file>` is empty), sync records the repo version as last applied. Without this, a change you copy back and commit leaves the old base in place, so the next upstream edit to the same lines shows as a false conflict (base A, live B, repo C, where C is simply newer than B). The guard above still holds: an uncommitted copy-back doesn't update the base, so discarding it still leaves a local change.
3. **Conflicts.** When run interactively and `code` is available, open VS Code's three-way merge editor (`code --wait --merge <live> <repo> <base> <result>`), write the result to live, and record the repo version as last applied. Otherwise leave live untouched and report the file with the command to resolve it later.
4. **Local-changes report.** For each file where live differs from repo, and each new file under a managed directory that isn't excluded, show `git diff --no-index` with the home path shown as `@HOME@`. In an interactive run, offer per file: copy back, skip, **ignore until it changes**, or open the diff in VS Code. Ignore (decided 2026-11-08, from Parked ideas option 1) stores a hash of the live file in the state folder; while the file stays the same, sync prints one `-` line for it instead of the diff and doesn't ask, and `-CopyBack` leaves it alone. When the file changes, or no longer differs from the repo, the stored hash is dropped. Skip only lasts for that run. **Copy back** writes the live content (home path → `@HOME@`) into the repo working tree. The user then reviews, stages the hunks they want (`git add -p`, VS Code, GitKraken), discards the rest and commits, as today. Sync never commits or pushes.
5. **Summary**: written, merged, conflicts, local changes, copied back, and a reminder to review `git diff`.

`-WhatIf` uses PowerShell's `SupportsShouldProcess` and changes nothing in the repo, live files or state; it prints what each step would do. Non-interactive runs (e.g. from `update.ps1` in a pipeline) skip prompts and only report.

### `install.ps1` and `update.ps1`

Straight ports of `install.sh` and `update.sh`, step for step and in the same order, with `-WhatIf` in place of `--dry-run`. They keep the same output helpers (`•`, `✓`, `-`, `!`, `~` lines and colours), idempotent "already installed → skip" checks, and the sudo keep-alive. Installers that are shell one-liners (`curl … | sh`) can still be run through `bash -c` on Linux, but with `pipefail` (`bash -o pipefail -c`), so a failed download fails the step instead of reporting success. Stage 0 fixed this in the bash `run` helper; the PowerShell helper must keep it, and must check the exit code of any native command it runs.

Differences from today:

- `stow` is dropped from the apt packages. The three `stow --adopt` steps are replaced by **one** sync step, `sync.ps1 -NoPull`, run **after all tools are installed and before setup actions**. So the order is: retire → tools → sync → setup actions, for both `install.ps1` and `update.ps1` (update upgrades tools instead of installing them, and its sync pulls). Installers that append to `~/.bashrc` (fnm, bun) then hit Debian's default file rather than a managed copy, and the first apply replaces it with the repo version, which already sets those PATHs. `sync.ps1` doesn't need a "sync only some entries" option. On a machine with no state, install does a first apply instead: it backs up any pre-existing file that differs from the repo (e.g. Debian's default `~/.bashrc`) into the state folder, writes the repo version, records state, and warns that it did so.
- Steps for confirmed retired tools are not ported; they become retire steps.
- The herdr integrations for Claude Code **and opencode** become **setup actions**: each registers through herdr's CLI (`herdr integration install claude` / `opencode`), skipping if already registered and still referenced from that agent's live config. opencode's `cli.json` keeps its relative `"./herdr-opencode"` plugin entry in the repo, since it's portable; herdr writes the plugin files themselves. Setup actions are idempotent and are run by `install.ps1` and `update.ps1` after their sync, so a migrated machine gets herdr's hook back, and any machine where it went missing gets it back on the next update. The herdr SessionStart hook is removed from the repo's `claude/.claude/settings.json`. GitKraken's marketplace and plugin entries are removed from it too. Both become local-only entries on each machine, written by their tools.
- **Herdr app support** (added 2026-11-08, after the port): `install.ps1` installs herdr-core on every Linux machine, since any of them can be added as a machine in the app, and `update.ps1` runs `herdr-core update`. On WSL only, `openssh-server` joins the apt packages, and a setup action installs `linux/sshd_config.d/herdr-wsl.conf` into `/etc/ssh/sshd_config.d/` (outside home, so not in the manifest), checks it with `sshd -t`, then enables and restarts ssh. If any of that fails it warns instead of failing the run: WSL distros share one network, so a second distro can't take port 2222. Adding the Windows public key to `authorized_keys` stays manual in Stage 1.
- `update.ps1` replaces `restow` with a call to `sync.ps1` and reports a stopped sync (non-zero exit) with a hint to resolve it and rerun `./sync.ps1`.
- Both scripts run `retire.ps1` first, and both take the same opt-out switch (e.g. `-SkipRetire`). Skipping it on a stow machine skips the migration too, so the switch prints a warning if links into the repo are still present.

### `bootstrap.sh`

Installs PowerShell 7 on Debian from Microsoft's apt repo if `pwsh` is missing, then runs `pwsh ./install.ps1` with any arguments passed through. Bash, `set -euo pipefail`, 2-space indent, idempotent.

### `retire.ps1`

A list of **retire steps**, one per removed tool, run in order. Each step checks whether anything of that tool is still present and skips with a `-` line if not, so running it on a machine that never had the tool, or running it again, does nothing. Supports `-WhatIf`. Steps stay in the list until the user decides no machine needs them, then get pruned. To remove a tool in future: delete its steps from `install.ps1`/`update.ps1`, its entries from the manifest and its files from the repo, then add a retire step here.

**Retire steps only remove; they never install.** When a tool moves to a different install method (e.g. Aspire from a .NET global tool to its own script), the retire step removes the old install and `install.ps1` installs the new one.

**Managed files mostly take care of themselves:** sync's "file removed from repo" rules already delete unchanged files and report changed ones. Retire steps cover what sync doesn't own: binaries, clones, caches, running processes, and files left behind from before sync tracked them.

**Confirmed** Stage 1 retire step:

1. **stow.** For existing stow machines. Find every symlink under `$HOME` (top level, `~/.config`, `~/.claude`, `~/.agents`) that points into the dotfiles repo. If its target still exists and is in the manifest, replace the link with a real copy (content unchanged, because the target is the repo file) and seed the state folder so sync treats it as already applied. If its target is gone (e.g. a retired tool's folder was removed from the repo) or not in the manifest, just delete the link. Then `apt remove stow` if installed.

Then, ported from Stage 0's bash `retire_*` functions with the same behaviour: OpenDesign, Bun, the superpowers clone, the Aspire .NET global tool (Aspire is installed with its own script on every machine), and dangling stow links (the last one is folded into the stow step above).

Because the repo layout of the remaining packages is unchanged, their links still work after the pull and before `install.ps1` runs, so the shell isn't broken in between. Docs tell the user to commit and push pending dotfile changes first, **except** tool-injected entries (herdr hook, GitKraken entries), which should be discarded. Their tools put them back (GitKraken on its own; herdr via the setup actions).

### Testing

- **Pester tests for `sync.ps1`** in a throwaway environment: a temp `HOME`, a bare remote, and two clones ("this machine" and "another machine"). They cover every row of the apply table, plus: placeholder round trip; local-only entries surviving repeated syncs; a clean JSON merge; a merge producing invalid JSON (the same key added on both sides) being treated as a conflict; a pull conflict stopping before any write; `-WhatIf` changing nothing (hashes of live files, repo and state unchanged, `HEAD` unchanged); `-NoPull` not touching git; copy-back writing placeholders; new files under a managed directory being reported; excluded paths being ignored.
- **Pester tests for `retire.ps1`'s stow step** (links into the repo replaced by copies with state seeded; dangling links deleted; links pointing elsewhere untouched; second run does nothing).
- **Script checks:** `install.ps1 -WhatIf`, `update.ps1 -WhatIf` and `retire.ps1 -WhatIf` run cleanly on this machine and list the expected steps.
- **End-to-end check on a throwaway WSL distro:** a fresh install via `bootstrap.sh`, then a stow-machine migration (install the pre-Stage-1 commit with the old `install.sh`, including the retired tools; check out the Stage 1 commit; run `bootstrap.sh`), checking that no links into the repo remain, the retired tools are gone, herdr's hook is registered, and a second sync reports nothing beyond expected local-only entries.

### Docs

At the end of Stage 1, update `AGENTS.md` (conventions, key commands, "Working on This Repo", including "how to remove a tool"), `linux/README.md`, `claude/README.md` and `README.md` to describe the manifest, `sync.ps1`, `retire.ps1` and the bootstrap instead of stow, plus a "Migrating a stow machine" section. Remove mentions of retired tools (anything in `windows/README.md` is left for Stage 2). Mark the chezmoi plan as superseded by this design.

## Parked ideas: local-only noise

Local-only entries (GitKraken's marketplace path, herdr's hook) differ from the repo forever, so they appear in every sync's local-changes report. If that becomes annoying, options in rough order of preference:

1. **Remember skips.** When a file is skipped, store its live content hash in state. Stay quiet until the file changes again. No config needed, but new changes in that file re-surface the old ones too. **Adopted 2026-11-08** as a separate "ignore until it changes" answer, so a plain skip doesn't hide anything (see the local-changes report above).
2. **A local-only list in the manifest:** per-file JSON paths (e.g. `extraKnownMarketplaces.gitkraken`) hidden from the report and never copied back. Explicit and shared, but needs keeping up to date.
3. **"Mark as local" during sync:** remembered in that machine's state. No list to write, but each machine has to learn it once.
4. **Spot the home path:** treat any setting not in the repo that contains this machine's home path as local. No config, but it's a guess and could hide a setting you meant to share.

## Left to the builder

- Exact manifest schema and file names within the rules above.
- Module structure and helper names in PowerShell.
- How sudo keep-alive is done in PowerShell.
- Prompt wording and key choices in the interactive copy-back.
- Whether directory entries create missing parent directories (they should) and how file modes are preserved (keep the target's existing mode and directory permissions; new files get default permissions).
- Name of the opt-out switch for retiring.

## Calls made during design (not decided by the user)

Check these while reading:

- Stage 0's retire steps are written in bash now and ported to `retire.ps1` in Stage 1, rather than waiting for Stage 1.
- `install.sh` switches from the pinned Node 24 to the latest LTS, so install and update agree.
- The dangling-link cleanup only deletes links that point into `~/.dotfiles` and no longer resolve.
- Keep the current repo directory layout instead of flattening it.
- `@HOME@` as the placeholder token.
- State as a plain folder at `~/.local/state/dotfiles/applied/`, not SQLite.
- Sync reads the repo **working tree**, and the last-applied copy only changes when sync writes a live file (protects local-only entries; see the apply rules). Since 2026-11-08 it also changes when live equals a committed repo file (avoids false conflicts after a committed copy-back).
- One sync step in `install.ps1`, after tools and before setup actions.
- Setup actions run on every install and update.
- `git pull --rebase` stated explicitly (matches `pull.rebase = true` in the repo's `.gitconfig`, without depending on it being applied yet).
- herdr's hook and GitKraken's entries come out of the repo's `settings.json` and become local-only.
- Skipping retire while stow links remain prints a warning.
- Removing `.stow-local-ignore` files.
- Pester for tests; `install.sh`/`update.sh` deleted once the PowerShell versions are verified.
- herdr-core on every Linux machine, not only WSL; sshd only on WSL.
- The sshd config has no `AllowUsers` line (usernames differ between machines; key-only login on localhost is enough).
- sshd setup failures warn instead of failing install/update.
- The Herdr app work is a separate task after the port, so the port stays step for step.

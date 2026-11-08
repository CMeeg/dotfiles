# Stage 1: Sync Engine and PowerShell Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace GNU Stow and the bash `install.sh`/`update.sh` with PowerShell 7 scripts that copy dotfiles as real files, sync them two ways with a last-applied state folder, retire old tools, and migrate existing stow machines.

**Architecture:** A manifest (`dotfiles.json`) lists every managed file or folder and its Linux target. `sync.ps1` compares three versions of each file (repo working tree with `@HOME@` filled in, the last-applied copy in `~/.local/state/dotfiles/applied/`, and the live file), applies repo changes, merges with `git merge-file` when both changed, and reports local changes for copy-back. `retire.ps1` ports Stage 0's retire steps and adds the stow migration. `install.ps1`/`update.ps1` are step-for-step ports of the bash scripts, ending with sync and setup actions. A follow-up task adds herdr-core everywhere and, on WSL, an sshd on `127.0.0.1:2222` so the Windows Herdr app can manage agents in the distro (the herdr TUI stays). Shared code lives in small modules under `lib/`. `bootstrap.sh` installs PowerShell, then runs `install.ps1`.

**Tech Stack:** PowerShell 7 (`pwsh`), Pester 6 (tests written in Pester 5 syntax, which Pester 6 runs unchanged; chosen 2026-11-08, replacing Pester 5), git (`merge-file`, `diff --no-index`, `ls-files`), bash (bootstrap and `curl | sh` installers), Debian 13 apt.

**Spec:** `docs/superpowers/specs/2026-11-06-cross-platform-dotfiles-design.md`, section "Stage 1 design" (plus the Decisions and Calls lists).

## Global Constraints

- PowerShell 7 only. Every `.ps1`/`.psm1` starts with `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`. 2-space indent for PowerShell, JSON, Shell (AGENTS.md).
- `bootstrap.sh`: `#!/usr/bin/env bash`, `set -euo pipefail`, 2-space indent, idempotent.
- Output style matches today's bash scripts exactly: `• ` (cyan) status, `  ✓ ` (green) ok, `  - ` (yellow) skip, `  ! ` (yellow) warn, `  ~ ` (blue) dry-run. No PowerShell `What if:` lines.
- `-WhatIf` changes nothing on disk, in the repo, in state or in running processes. Commands that change things go through `Invoke-Step`; file writes go through helpers that honour the dry-run flag. Each script calls `Set-DryRun ([bool]$WhatIfPreference)` and then sets `$WhatIfPreference = $false`: PowerShell's own `-WhatIf` otherwise reaches cmdlets inside the modules (found 2026-11-08: it skipped a `Remove-Item` of a temp folder and printed a `What if:` line).
- Shell one-liners run via `bash -o pipefail -c`, and every native command's exit code is checked (spec: a failed download fails the step).
- Retire steps only remove; they never install.
- Scripts never commit or push.
- Files are read and written byte-exact as UTF-8 without BOM (no line-ending or trailing-newline changes).
- The placeholder is `@HOME@`. Stage 1 handles the Linux home form only.
- State lives at `$env:DOTFILES_STATE`, default `<home>/.local/state/dotfiles`; the repo at `$env:DOTFILES_REPO`, default `<home>/.dotfiles`; home is `$env:HOME`. Never use PowerShell's `$HOME`/`~` directly (it doesn't follow `$env:HOME` changes, which the tests rely on).
- Markdown: no hard wrapping.

## Review Focus

- **Home path prefix collisions on copy-back:** with home `/home/meeg`, a value `/home/meeg2/x` must stay as written; only `/home/meeg` followed by `/`, a quote, whitespace, `:` or end of text becomes `@HOME@`. Owned by Task 2, `ConvertTo-HomePlaceholder leaves a longer username alone`.
- **A live file that's still a stow link into the repo** (sync run before the stow retire, or with `-SkipRetire`). Writing through it would edit the repo file. Expected: `sync.ps1` refuses with a message pointing at `retire.ps1` and exits 1 before writing anything. Owned by Task 3, `refuses to write through a link into the repo`.
- **Non-ASCII content and missing trailing newlines** (starship's Nerd Font glyphs, files without a final newline) must round-trip byte-exact through apply, merge and copy-back. Owned by Task 3, `keeps unicode and a missing final newline byte-exact`.
- **herdr reports "current" but the agent's config lacks its entry** (e.g. the repo just dropped the Claude hook, so the live `settings.json` lost it; herdr's status only checks its own plugin files). Expected: the setup action reinstalls that agent's integration. Owned by Task 7, `reinstalls when the settings file lacks the hook` and `opencode: installs when cli.json lacks the herdr plugin`.
- **A second WSL distro can't take port 2222** (all distros share one network, so the throwaway distro in Task 10 hits this). Expected: the sshd setup action warns and install/update carry on; a config that fails `sshd -t` is never loaded. Owned by Task 8, `sshd: a failed restart warns and doesn't throw` and `sshd: doesn't restart when sshd -t fails`.
- **Missing parent directories on a fresh machine** (`~/.config/herdr/` doesn't exist yet). Expected: created, file written. Owned by Task 3, `creates missing parent directories`.

---

### Task 1: PowerShell, Pester and the common module

**Files:**
- Create: `bootstrap.sh` (executable), `lib/Common.psm1`, `tests/Common.Tests.ps1`

**Interfaces:**
- Produces, in `lib/Common.psm1`:
  - `Get-HomeDir` → `[string]`, `$env:HOME`.
  - `Get-RepoDir` → `[string]`, `$env:DOTFILES_REPO` or `<home>/.dotfiles`.
  - `Get-StateDir` → `[string]`, `$env:DOTFILES_STATE` or `<home>/.local/state/dotfiles`.
  - `Resolve-TargetPath [string]$Path` → `[string]`: leading `~` → home; `%VAR%` expanded with `[Environment]::ExpandEnvironmentVariables`.
  - `Set-DryRun [bool]$Enabled`, `Test-DryRun` → `[bool]`. Every module reads this one flag; scripts set it from `$WhatIfPreference` at start.
  - `Write-Status`, `Write-Ok`, `Write-Skip`, `Write-Warn`, `Write-Dry` — each `[string]$Message`, exact prefixes from Global Constraints.
  - `Invoke-Step [string]$Command` → nothing. Dry-run: `Write-Dry $Command`. Otherwise runs `bash -o pipefail -c $Command`; on non-zero exit, `Write-Warn "Command failed (exit code N): $Command"` and throws.
  - `Test-Command [string]$Name` → `[bool]` (`Get-Command -ErrorAction SilentlyContinue`).

- [x] **Step 1: Write `bootstrap.sh`**

  If `pwsh` is missing: if no `/etc/apt/sources.list.d/microsoft-prod.*` exists, install `curl` if it's missing (a fresh Debian image has none; found in Task 10, 2026-11-08), then download `https://packages.microsoft.com/config/debian/$VERSION_ID/packages-microsoft-prod.deb` (`VERSION_ID` from `/etc/os-release`) and `sudo dpkg -i` it, then `sudo apt update`; then `sudo apt install -y powershell`. Then `exec pwsh -NoProfile -File "$(dirname "$0")/install.ps1" "$@"`. `install.ps1` doesn't exist until Task 7, so in this task stop before the `exec` when `install.ps1` is missing and print `pwsh installed — install.ps1 not found yet`.

- [x] **Step 2: Install PowerShell and Pester on this machine**

  ```bash
  ./bootstrap.sh                                   # expect: installs powershell, prints the "not found yet" line
  pwsh -NoProfile -c '$PSVersionTable.PSVersion.Major'   # expect: 7
  pwsh -NoProfile -c 'Install-Module Pester -MinimumVersion 6.0 -Scope CurrentUser -Force; (Get-Module Pester -ListAvailable | Sort-Object Version -Desc | Select-Object -First 1).Version.Major'   # expect: 6
  ```

- [x] **Step 3: Write the failing tests** in `tests/Common.Tests.ps1` (Pester 5 syntax, run by Pester 6, `BeforeAll { Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force }`)

  | Test | Assert |
  |---|---|
  | `Resolve-TargetPath expands a leading tilde from $env:HOME` | with `$env:HOME='/tmp/h'`, `~/.bashrc` → `/tmp/h/.bashrc` |
  | `Get-StateDir honours DOTFILES_STATE` | set → that value; unset → `<home>/.local/state/dotfiles` |
  | `Invoke-Step prints a dry line and runs nothing in dry-run` | `Set-DryRun $true`; `Invoke-Step "touch $tmp/x"` → `$tmp/x` absent; output contains `~ touch` |
  | `Invoke-Step fails a pipeline whose first command fails` | `Invoke-Step 'false | cat'` throws; output contains `Command failed (exit code 1)` |
  | `Invoke-Step runs a succeeding command` | `Invoke-Step "touch $tmp/x"` → `$tmp/x` exists |
  | `Write-Skip uses the bash scripts' prefix` | output (via `6>&1`) contains `  - hello` |

- [x] **Step 4: Run the tests to verify they fail**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests/Common.Tests.ps1 -Output Detailed'`
  Expected: all fail (module not found).

- [x] **Step 5: Implement `lib/Common.psm1`**

- [x] **Step 6: Run the tests to verify they pass**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests/Common.Tests.ps1 -Output Detailed'`
  Expected: 6 passed, 0 failed.

- [x] **Step 7: Checkpoint: user reviews and commits** (suggested: `add PowerShell bootstrap and common module`)

---

### Task 2: Manifest and home-path placeholder

**Files:**
- Create: `dotfiles.json`, `lib/Manifest.psm1`, `tests/Manifest.Tests.ps1`

**Interfaces:**
- Consumes: `Get-HomeDir`, `Resolve-TargetPath` (Task 1).
- Produces, in `lib/Manifest.psm1`:
  - `Get-ManagedFiles [string]$RepoDir` → array of `[pscustomobject]@{ Source = 'bash/.bashrc'; Target = '/home/meeg/.bashrc'; DirectoryEntry = $null or the entry object }` for the current OS (`linux` key in Stage 1; the module also picks `windows` on Windows and `macos` on macOS, where `macos` is *provisional*: a hook for later, not used in this plan). File entries map one to one. Directory entries expand to `git -C $RepoDir ls-files -co --exclude-standard -- <source>` (tracked plus untracked-not-ignored, so `.gitignore` applies) minus `exclude` globs, each with `Target` = entry target + the path under the entry. Entries without a key for the OS are skipped.
  - `Get-ManagedDirectories [string]$RepoDir` → array of `[pscustomobject]@{ Source; Target; Exclude = [string[]] }`.
  - `Test-ExcludedPath [string]$RelativePath, [string[]]$Patterns` → `[bool]`; `**` matches any depth, `*` within one segment.
  - `Expand-HomePlaceholder [string]$Text, [string]$HomeDir` → `[string]`: every `@HOME@` → `$HomeDir`.
  - `ConvertTo-HomePlaceholder [string]$Text, [string]$HomeDir` → `[string]`: `$HomeDir` → `@HOME@` only where followed by `/`, `"`, `'`, whitespace, `:` or end of text.
- `dotfiles.json` schema: `{ "entries": [ { "source": "<repo path>", "linux": "<target>", "exclude": ["<glob>"] } ] }`, `exclude` optional and directory entries only.

- [x] **Step 1: Write `dotfiles.json`**

  File entries: `bash/.bash_aliases`, `bash/.bash_logout`, `bash/.bashrc`, `bash/.profile` → `~/<name>`; `git/.gitconfig` → `~/.gitconfig`; `starship/.config/starship.toml`, `superfile/.config/superfile/config.toml`, `herdr/.config/herdr/config.toml`, `opencode/.config/opencode/opencode.jsonc`, `opencode/.config/opencode/cli.json`, `claude/.claude/settings.json`, `claude/.claude/CLAUDE.md` → the same path under `~`. No directory entries: none of today's packages needs one, but `Get-ManagedFiles` still supports them (tested with the fixture repos here and in Task 3). Not listed: READMEs, `.stow-local-ignore`, `claude/.claude/local-plugins` (loaded from the repo by Claude Code via `CLAUDE_CODE_PLUGIN_DIRS` and by opencode via the `skills` list in `opencode.jsonc`).

- [x] **Step 2: Write the failing tests** in `tests/Manifest.Tests.ps1`. Each test builds a small temp git repo with its own `dotfiles.json`.

  | Test | Assert |
  |---|---|
  | `maps a file entry to its expanded target` | `bash/.bashrc` → `<home>/.bashrc` |
  | `expands a directory entry to its files` | repo has `skills/a/SKILL.md`, `skills/b/x.md` → two files with targets under the entry target |
  | `drops excluded and gitignored files` | `skills/synced/s.md` with `exclude synced/**`, and `skills/tmp.log` gitignored → neither returned |
  | `skips entries with no key for this OS` | entry with only `windows` → not returned |
  | `real manifest covers every stow package file` | for this repo's `dotfiles.json`, `Source` set equals `git ls-files bash git starship superfile herdr opencode claude` minus `README.md`, `.stow-local-ignore` and `claude/.claude/local-plugins/**` |
  | `Expand-HomePlaceholder fills every token` | `"@HOME@/a @HOME@/b"` → `"/home/u/a /home/u/b"` |
  | `ConvertTo-HomePlaceholder replaces the home path before / and "` | `'"/home/u/x" /home/u'` → `'"@HOME@/x" @HOME@'` |
  | `ConvertTo-HomePlaceholder leaves a longer username alone` | `/home/u2/x` unchanged with home `/home/u` |
  | `placeholder round-trips` | `ConvertTo-HomePlaceholder (Expand-HomePlaceholder $t)` equals `$t` for a text with three tokens |

- [x] **Step 3: Run the tests to verify they fail**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests/Manifest.Tests.ps1 -Output Detailed'`
  Expected: all fail (module not found).

- [x] **Step 4: Implement `lib/Manifest.psm1`**

- [x] **Step 5: Run the tests to verify they pass**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests -Output Detailed'`
  Expected: 15 passed (6 + 9), 0 failed.

- [ ] **Step 6: Checkpoint: user reviews and commits** (suggested: `add dotfiles manifest and home placeholder`)

---

### Task 3: State and the apply engine

**Files:**
- Create: `lib/State.psm1`, `lib/Sync.psm1`, `sync.ps1`, `tests/TestHelpers.psm1`, `tests/Sync.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces, in `lib/State.psm1` (all paths absolute; targets must be under home, else throw):
  - `Get-AppliedPath [string]$Target` → `<state>/applied/<target relative to home>`.
  - `Read-Applied [string]$Target` → `[string]` or `$null`; `Write-Applied [string]$Target, [string]$Content`; `Remove-Applied [string]$Target`; `Get-AppliedTargets` → `[string[]]` of absolute targets that have an applied copy.
  - `Backup-LiveFile [string]$Target` → `[string]` backup path under `<state>/backup/<yyyyMMdd-HHmmss>/<relative>`.
- Produces, in `lib/Sync.psm1`:
  - `Get-SyncAction -Repo <string|$null> -Base <string|$null> -Live <string|$null> -InRepo <bool>` → one of `WriteRepo`, `RecordBase`, `None`, `LocalChange`, `Merge`, `Conflict`, `DeletedLocally`, `DeleteLive`, `RemovedButChanged`. Pure; implements the spec's apply table:

    | InRepo | Base | Live vs Repo/Base | Action |
    |---|---|---|---|
    | yes | none | live missing | `WriteRepo` |
    | yes | none | live == repo | `RecordBase` |
    | yes | none | live ≠ repo | `Conflict` |
    | yes | exists | live == repo | `None` |
    | yes | exists | live missing | `DeletedLocally` |
    | yes | exists | live == base | `WriteRepo` |
    | yes | exists | repo == base | `LocalChange` |
    | yes | exists | otherwise | `Merge` |
    | no | exists | live missing | `DeletedLocally` (then forget) |
    | no | exists | live == base | `DeleteLive` |
    | no | exists | live ≠ base | `RemovedButChanged` |
  - `Invoke-Sync [switch]$NoPrompt, [switch]$InitialApply` → summary `[pscustomobject]@{ Written; Merged; Conflicts; LocalChanges; NewLocalFiles; Deleted; Reported; CopiedBack }` (arrays of target paths). In this task it handles every action except `Merge`, which is reported as a conflict until Task 4. Writes go live first, then state; the last-applied copy is updated only on `WriteRepo`/`RecordBase` (and merge results in Task 4), never on `None`/`LocalChange`. `DeleteLive` removes the live file and its applied copy. `RemovedButChanged` and "removed + live missing" report once and remove the applied copy (the file is no longer managed). `-InitialApply` turns a no-base `Conflict` into `Backup-LiveFile` + `WriteRepo` + `Write-Warn` naming the backup.
  - Before any write, if a managed target is a symlink whose target resolves inside the repo, `Invoke-Sync` throws `"<target> is still a stow link — run ./retire.ps1 first"`.
- `sync.ps1 [-NoPull] [-NoPrompt] [-InitialApply] [-WhatIf]` (`[CmdletBinding(SupportsShouldProcess)]`): imports the modules from `$PSScriptRoot/lib`, `Set-DryRun $WhatIfPreference`, (pull: Task 4), `Invoke-Sync`, prints the summary. Exit 0 on success (conflicts and local changes are reported, not failures), 1 on a thrown error.
- `tests/TestHelpers.psm1`: `New-SyncFixture` → creates `TMP`, sets `$env:HOME`, `$env:DOTFILES_REPO`, `$env:DOTFILES_STATE`, `GIT_AUTHOR_*`/`GIT_COMMITTER_*`; builds a bare remote seeded with a `dotfiles.json` (file entries `plainrc` → `~/.plainrc`, `otherrc` → `~/.otherrc`, `cfg/app.json` → `~/.config/app/app.json`; directory entry `skills` → `~/.skills` excluding `synced/**`) and those files; clones it to `$env:DOTFILES_REPO` and to `<TMP>/other`. `Invoke-SyncScript [string[]]$Arguments` → `@{ ExitCode; Output }` by running `pwsh -NoProfile -File <repo root>/sync.ps1` in a child process. `Set-Upstream [string]$Path, [string]$Content` commits and pushes from `<TMP>/other`.

- [x] **Step 1: Write the failing tests** in `tests/Sync.Tests.ps1`

  `Get-SyncAction`: one table-driven `It` per row of the table above (11 cases), plus:

  | Test (via `Invoke-SyncScript -NoPull -NoPrompt`) | Arrange | Assert |
  |---|---|---|
  | `writes repo files on a fresh machine` | no live files, no state | live files equal repo; applied copies exist |
  | `creates missing parent directories` | `~/.config/app/` absent | `~/.config/app/app.json` written |
  | `records state when live already matches` | live files equal repo, no state | applied copies exist, live unchanged |
  | `applies a repo change` | sync; edit repo `plainrc` (working tree, uncommitted); sync | live `.plainrc` has the edit; applied copy has it |
  | `keeps a local change and reports it` | sync; edit live `.plainrc`; sync | live keeps the edit; output names `.plainrc` as a local change; applied copy unchanged |
  | `local-only entry survives a copy-back that is then discarded` | sync; add a line to live `.plainrc`; copy it into the repo working tree by hand; sync; `git checkout -- plainrc` in the repo; sync | live still has the line after the last sync |
  | `first sight conflict leaves live alone without -InitialApply` | live `.plainrc` differs, no state | live unchanged; output has a conflict for `.plainrc` |
  | `-InitialApply backs up and replaces` | as above with `-InitialApply` | live equals repo; backup file under `<state>/backup/` has the old content; output has `!` naming it |
  | `reports a locally deleted file and doesn't recreate it` | sync; delete live `.otherrc`; sync | `.otherrc` still absent; output names it |
  | `deletes a file removed from the repo when unchanged` | sync; remove `otherrc` from the manifest; sync | live `.otherrc` gone; applied copy gone |
  | `reports a removed file that changed locally, once` | sync; edit live `.otherrc`; remove from manifest; sync twice | live kept; first output names it; second doesn't |
  | `reports a new file in a managed directory` | sync; create `~/.skills/new/SKILL.md` | output names it as a new local file |
  | `ignores excluded files in a managed directory` | create `~/.skills/synced/x.md` | output doesn't name it |
  | `refuses to write through a link into the repo` | replace live `.plainrc` with a symlink to the repo's `plainrc`; edit repo `plainrc` | exit 1; output contains `retire.ps1`; repo file unchanged by sync |
  | `keeps unicode and a missing final newline byte-exact` | repo `plainrc` = `"glyph  ✓ é"` with no final newline | live bytes equal repo bytes |
  | `-WhatIf changes nothing` | edit repo `plainrc` after a first sync | `-WhatIf` exit 0; SHA-256 of every live, repo and state file unchanged; output contains `~ ` |
  | `fills @HOME@ on apply` | repo `cfg/app.json` = `{"p":"@HOME@/x"}` | live contains `$env:HOME/x` |

- [x] **Step 2: Run the tests to verify they fail**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests/Sync.Tests.ps1 -Output Detailed'`
  Expected: all fail (module or script not found).

- [x] **Step 3: Implement `lib/State.psm1`, `lib/Sync.psm1` and `sync.ps1`**

  Read and write with `[IO.File]::ReadAllText/WriteAllText` and `[Text.UTF8Encoding]::new($false)`. Detect a link into the repo with `(Get-Item -Force $target).LinkTarget` resolved against the link's folder.

- [x] **Step 4: Run the tests to verify they pass**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests -Output Detailed'`
  Expected: all passed (15 + 28), 0 failed.

- [ ] **Step 5: Checkpoint: user reviews and commits** (suggested: `add sync engine apply rules and state`)

---

### Task 4: Pull, three-way merge and conflicts

**Files:**
- Create: `lib/Json.psm1`, `tests/Json.Tests.ps1`
- Modify: `lib/Sync.psm1`, `sync.ps1`, `tests/Sync.Tests.ps1`

**Interfaces:**
- Consumes: Task 3.
- Produces, in `lib/Json.psm1` (added 2026-11-08, see the spec's apply table): `Find-JsonDuplicateKey [string]$Text` → `[string]` (the first key that appears twice in one object) or `$null`. Skips strings and `//`/`/* */` comments, so it works for `.jsonc`; doesn't validate the rest of the syntax (`ConvertFrom-Json` does that).
- Produces, in `lib/Sync.psm1`:
  - `Invoke-RepoPull [string]$RepoDir` → `[bool]`. If `git status --porcelain --untracked-files=no` is non-empty: `git stash push -m sync.ps1`. Then `git pull --rebase`, then `git stash pop` if stashed. Returns `$false` (after `Write-Warn` listing `git diff --name-only --diff-filter=U`) if any step fails or unmerged files remain. Dry-run: `Write-Dry "git pull --rebase (stashing local changes if needed)"`, returns `$true`.
  - `Invoke-ThreeWayMerge [string]$Live, [string]$Base, [string]$Repo, [string]$Target` → `[pscustomobject]@{ Clean = [bool]; Content = [string] }` using temp files and `git merge-file -p -L live -L base -L repo`. Exit 0 = clean; > 0 = conflicts; < 0 = throw. For `.json`/`.jsonc` targets a clean merge that `ConvertFrom-Json` rejects, or that has a key twice in one object (`Find-JsonDuplicateKey`), is `Clean = $false`.
  - `Invoke-Sync` now handles `Merge`: clean → write content to live, write **repo** content as the applied copy, list under `Merged`. Not clean → conflict. Conflicts: if prompting is allowed (`-not $NoPrompt`, input and output not redirected) and `Test-Command code`, run `code --wait --merge <live> <repo tmp> <base tmp> <result tmp>`, write the result to live and the repo content as applied; otherwise leave live untouched and report the file with `Write-Warn "Conflict: <target> — run ./sync.ps1 in a terminal to merge it in VS Code"`.
- `sync.ps1`: unless `-NoPull`, call `Invoke-RepoPull` first; on `$false`, exit 1 without applying.
- `Invoke-Sync` throws (so `sync.ps1` exits 1) before any write if `git diff --name-only --diff-filter=U` lists files: a pull or stash pop that stopped on a conflict leaves markers in the working tree, and `-NoPull` runs (including `install.ps1`'s) would otherwise copy them into live files. Added 2026-11-08.

- [x] **Step 1: Write the failing tests**

  | Test | Arrange | Assert |
  |---|---|---|
  | `applies an upstream change` | first sync; `Set-Upstream otherrc b`; sync (with pull) | exit 0; live `.otherrc` = `b` |
  | `merges non-overlapping edits to the same file` | `plainrc` has 5 lines; sync; local edits line 1; upstream edits line 5; sync | live has both edits; `Merged` names it; applied copy equals repo |
  | `overlapping edits are a conflict and live is kept` | local and upstream change line 1 differently; sync `-NoPrompt` | exit 0; live has the local edit; output contains `Conflict:` and `.plainrc` |
  | `a clean merge that breaks JSON is a conflict` | `cfg/app.json` = `a`, `m`, `b` on separate lines; local adds `"c": 3,` after `"a": 1,` and upstream adds `"c": 4,` after `"m": 0,`, so `git merge-file` reports clean but the result has `c` twice (`ConvertFrom-Json` accepts duplicate keys, and a missing comma can only come from adjacent edits, which already conflict) | live unchanged; output contains `Conflict:` |
  | `merges a clean JSON change` | as above, but upstream adds `"d": 4,` | live has both keys and parses; `Merged` names it |
  | `a pull conflict stops before any write` | commit a local change to repo `plainrc` and push a conflicting one upstream; also change upstream `otherrc` | exit 1; live `.otherrc` unchanged; output names the unmerged file |
  | `refuses to apply while the repo has unresolved git conflicts` (added 2026-11-08) | a pull stops on a conflict in `plainrc`; then sync `-NoPull` | exit 1; output names `plainrc`; live `.plainrc` unchanged (the repo file holds conflict markers) |
  | `-NoPull doesn't touch git` | `Set-Upstream otherrc b` | `-NoPull` exit 0; repo `HEAD` unchanged; live `.otherrc` unchanged |
  | `stashes and restores uncommitted repo changes around the pull` | uncommitted edit to repo `plainrc`; upstream change to `otherrc`; sync | exit 0; repo working tree still has the `plainrc` edit; live `.otherrc` updated |

  `tests/Json.Tests.ps1`: `finds a key repeated in one object`, `finds a repeat in a nested object`, `allows the same key in different objects`, `ignores keys inside strings and comments`, `returns $null for an empty object`.

- [x] **Step 2: Run the tests to verify they fail**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests/Sync.Tests.ps1, tests/Json.Tests.ps1 -Output Detailed'`
  Expected: the 8 new sync tests and the Json tests fail; Task 3's still pass.

- [x] **Step 3: Implement `Invoke-RepoPull`, `Invoke-ThreeWayMerge` and the merge/conflict handling**

- [x] **Step 4: Run the tests to verify they pass**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests -Output Detailed'`
  Expected: all passed, 0 failed.

- [ ] **Step 5: Checkpoint: user reviews and commits** (suggested: `add pull and three-way merge to sync`)

---

### Task 5: Local-changes report and copy-back

**Files:**
- Modify: `lib/Sync.psm1`, `sync.ps1`, `tests/Sync.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces, in `lib/Sync.psm1`:
  - `Show-LocalChange [pscustomobject]$File` → prints `git diff --no-index --color <repo tmp> <live tmp>` where both temp copies have the home path converted to `@HOME@`. For a new file, diffs against an empty file.
  - `Invoke-CopyBack [pscustomobject]$File` → writes `ConvertTo-HomePlaceholder (live content)` to `<repo>/<Source>` (creating folders for new files under a directory entry). Never touches state. Dry-run: `Write-Dry "Copy back <target> → <source>"`.
  - In `Invoke-Sync`, after applying: for each local change and new local file, show the diff; when prompting is allowed, ask `[c]opy back, [s]kip, [d]iff in VS Code (left: repo, right: this machine; view only)` (VS Code: `code --wait --diff <repo tmp> <live tmp>`, then ask again; the diff shows temp copies, so edits there are discarded and copy-back always writes the whole live file — decided 2026-11-08). `-NoPrompt` only shows the diffs.
  - Summary lines at the end: counts for written, merged, conflicts, local changes, new local files, deleted, copied back; when anything was copied back, `Write-Warn "Review with 'git diff' in <repo>, stage what you want, then commit and push"`.
- `sync.ps1` gains `-CopyBack` (non-interactive: copy back every local change and new local file without asking). Used by the tests and available to the user.

- [x] **Step 1: Write the failing tests**

  | Test | Arrange | Assert |
  |---|---|---|
  | `-CopyBack writes the live change into the repo with placeholders` | sync; live `cfg/app.json` gets `"q":"<home>/y"` | `-NoPull -CopyBack` exit 0; repo `cfg/app.json` contains `"q":"@HOME@/y"`; applied copy unchanged |
  | `-CopyBack adds a new file under a managed directory` | create `~/.skills/new/SKILL.md` | repo has `skills/new/SKILL.md` with the same content |
  | `report shows the home path as @HOME@` | live `.plainrc` gains `<home>/z` | `-NoPrompt` output contains `@HOME@/z` and not `<home>/z` |
  | `-NoPrompt doesn't copy back` | local change | repo file unchanged |
  | `-CopyBack -WhatIf changes nothing` | local change | repo file unchanged; output contains `~ Copy back` |

- [x] **Step 2: Run the tests to verify they fail**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests/Sync.Tests.ps1 -Output Detailed'`
  Expected: the 5 new tests fail.

- [x] **Step 3: Implement the report, prompt, `-CopyBack` and summary**

- [x] **Step 4: Run the tests to verify they pass**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests -Output Detailed'`
  Expected: all passed, 0 failed.

- [ ] **Step 5: Checkpoint: user reviews and commits** (suggested: `add local-change report and copy-back to sync`)

---

### Task 6: `retire.ps1`

**Files:**
- Create: `lib/Retire.psm1`, `retire.ps1`, `tests/Retire.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 1–3 (`Get-ManagedFiles`, `Expand-HomePlaceholder`, `Write-Applied`, `Invoke-Step`, `Test-DryRun`).
- Produces, in `lib/Retire.psm1`, one function per step, each idempotent with a single `Write-Skip` when there's nothing to do, ported from `lib/retire.sh` with the same messages:
  - `Invoke-RetireStow` — finds symlinks (`$HOME` top level, `~/.config`, `~/.claude`, `~/.agents`, recursively except the top level; unreadable folders ignored) whose target resolves inside the repo. Managed and existing target → replace the link with a real file holding `Expand-HomePlaceholder` of the repo content, and `Write-Applied` the same content. Otherwise (dangling, or not in the manifest, e.g. a gitignored file left in the repo) → delete the link and remove parents left empty, never `$HOME`. Same `~/.agents` "left in place" warning rule as Stage 0. Then, if `dpkg-query` shows `stow` installed, `Invoke-Step 'sudo apt remove -y stow'`.
  - `Invoke-RetireOpenDesign`, `Invoke-RetireBun`, `Invoke-RetireSuperpowersClone`, `Invoke-RetireAspireDotnetTool` — same behaviour as the bash versions (including the bracketed `pkill` pattern with `|| true`, and the Aspire message telling the user to run `./install.ps1`).
  - `Invoke-RetireSteps` — `Write-Status "Retiring removed tools..."` then the five in that order.
  - `Test-StowLinksPresent` → `[bool]`, any symlink into the repo in those folders.
- `retire.ps1 [-WhatIf]`: imports modules, `Set-DryRun`, `Invoke-RetireSteps`.

- [x] **Step 1: Write the failing tests** in `tests/Retire.Tests.ps1` (temp `HOME`, a temp repo with a small `dotfiles.json`; fake `dpkg-query`, `pgrep`, `pkill`, `dotnet` scripts on `PATH` where needed)

  | Test | Assert |
  |---|---|
  | `replaces a managed stow link with a real copy and seeds state` | `~/.plainrc` → relative link to repo `plainrc`; after: regular file, same content, applied copy equal |
  | `fills @HOME@ when replacing a link` | repo file contains `@HOME@/x` → live file has `<home>/x` |
  | `deletes a link to an unmanaged repo file` | `~/.config/old/x.conf` → repo `old/.config/old/x.conf` (exists, not in manifest) → link gone, `~/.config/old` gone if empty, repo file kept |
  | `deletes a dangling repo link and empty parents` | `~/.agents/skills/x/SKILL.md` dangling → link gone; `~/.agents` gone |
  | `leaves links outside the repo alone` | `~/.config/foo` → `/nonexistent` → still there |
  | `warns when ~/.agents keeps foreign files` | as Stage 0 test → output contains `left in place` |
  | `second run is a no-op` | output has `-` lines only |
  | `-WhatIf changes nothing` | link still a link; no state written; output contains `~ ` |
  | `removes stow when installed` | fake `dpkg-query` reports installed; fake `sudo` logs → log contains `apt remove -y stow` |
  | `OpenDesign: removes the folder even if pkill finds nothing` | fake `pgrep` exit 0, `pkill` exit 1 → `~/.opendesign` gone |
  | `Bun, superpowers clone, Aspire tool` | one test each, mirroring the Stage 0 bash tests (removed; skip when absent; Aspire uninstall call logged, nothing installed) |
  | `Test-StowLinksPresent` | true with a repo link present; false after `Invoke-RetireStow` |

- [x] **Step 2: Run the tests to verify they fail**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests/Retire.Tests.ps1 -Output Detailed'`
  Expected: all fail.

- [x] **Step 3: Implement `lib/Retire.psm1` and `retire.ps1`**

- [x] **Step 4: Run the tests to verify they pass**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests -Output Detailed'`
  Expected: all passed, 0 failed.

- [x] **Step 5: Dry-run on this machine**

  Run: `pwsh -NoProfile ./retire.ps1 -WhatIf`
  Expected: `~` lines replacing each link into the repo under `~`, `~/.config`, `~/.claude` (bash, git, starship, superfile, herdr, opencode, claude files, including `~/.claude/CLAUDE.md`), deleting any links whose target is gone or not in the manifest (none expected once this machine's dangling links are cleaned up), and `~ sudo apt remove -y stow`; the other steps print `-`. Nothing changes.

- [ ] **Step 6: Checkpoint: user reviews and commits** (suggested: `add retire.ps1 with stow migration`)

---

### Task 7: Port `install.sh` and `update.sh`, plus setup actions

**Files:**
- Create: `lib/Tools.psm1`, `lib/Setup.psm1`, `install.ps1`, `update.ps1`, `tests/Tools.Tests.ps1`, `tests/Setup.Tests.ps1`
- Modify: `claude/.claude/settings.json` (remove the herdr `SessionStart` hook block, keeping `"hooks": {}` only if other hooks exist, otherwise remove the `hooks` key), `bootstrap.sh` (drop the "not found yet" branch)

**Interfaces:**
- Consumes: Tasks 1, 3, 6.
- Produces, in `lib/Tools.psm1` (ports of `lib/gitkraken.sh` and the helpers): `$GitKrakenDebUrl`, `Get-GitKrakenVersionFromUrl [string]$Url` → `[string]`/`$null`, `Get-GitKrakenLatestVersion` → `[string]`/`$null` (`curl -fsSL --max-time 20 -r 0-0 -o /dev/null -w '%{url_effective}'`, stderr discarded), `Test-GitKrakenNeedsUpdate [string]$Installed, [string]$Latest` → `[bool]`, `Get-LatestNodeLts` → `[string]`/`$null`, `Test-AptInstalled [string]$Package` → `[bool]`, `Get-FnmDefault` → `[string]`/`$null`.
- Produces, in `lib/Setup.psm1`:
  - `Invoke-HerdrIntegration [ValidateSet('claude','opencode')][string]$Agent` — skip with `Write-Skip` if `herdr` is missing, or if the agent itself isn't installed (`claude` / `opencode` not on `PATH`). Otherwise install (`Invoke-Step "herdr integration install $Agent"`) unless `herdr integration status` reports `<agent>: current` **and** the agent's live config still references herdr:
    - `claude`: `~/.claude/settings.json` contains `herdr-agent-state.sh` (the repo no longer carries this hook: herdr writes it with an absolute path, and the repo's hand-edited `$HOME` version isn't recognised by herdr as its own, which led to duplicate hooks);
    - `opencode`: `~/.config/opencode/cli.json` contains `herdr-opencode` (the repo's `cli.json` keeps its relative `"./herdr-opencode"` entry, which is portable; herdr writes the plugin files under `~/.config/opencode/plugins/` and `~/.config/opencode/herdr-opencode/`, which aren't managed).
  - `Invoke-SetupActions` — `Write-Status "Running setup actions..."`, then `Invoke-HerdrIntegration claude` and `Invoke-HerdrIntegration opencode`.
- `install.ps1 [-SkipRetire] [-WhatIf]`, `update.ps1 [-SkipRetire] [-WhatIf]`: same steps, order, messages and skip checks as today's bash scripts, with these changes from the spec:
  - Order: sudo keep-alive → retire (or, with `-SkipRetire`, `Write-Skip` plus `Write-Warn` if `Test-StowLinksPresent`) → tools → sync → setup actions → the closing "Done" lines.
  - `install.ps1`: `stow` dropped from the apt packages; the three stow steps replaced by one `sync.ps1 -NoPull` call, with `-InitialApply` when `Get-StateDir` doesn't exist yet. `update.ps1`: `restow` replaced by `sync.ps1` (with pull); a non-zero exit becomes `Write-Warn "Dotfiles sync stopped — resolve the conflict above, then run ./sync.ps1"`.
  - Sync runs in the same terminal (not redirected) so its prompts work.
  - Both scripts put every tool folder that `bash/.bashrc` adds to `PATH` (`~/.local/bin`, `~/.local/share/fnm`, `~/.opencode/bin`, `~/.aspire/bin`; listed once in `Get-ToolBinDirectories` in `lib/Tools.psm1`, with a test that fails if `.bashrc` gains one the list lacks) first on their own `PATH` at the start, with `Add-PathEntry` from `lib/Common.psm1`. On a fresh machine the shell that started the script predates the tools: the setup actions skipped herdr and opencode as "not installed", and a second `install.ps1` run reinstalled fnm and opencode. Found in Task 10, 2026-11-08.
  - `install.ps1` runs opencode's installer with `--no-modify-path`, as `bash/.bashrc` already adds `~/.opencode/bin`; without it the installer appended a `PATH` line to the managed `~/.bashrc`. Found in Task 10, 2026-11-08.
  - In a dry run with stow links still present, the sync step prints `Write-Skip "Can't preview sync while stow links remain — run ./retire.ps1, then ./sync.ps1 -WhatIf"` instead of running sync, which would refuse: retire's dry run leaves the links in place. Added 2026-11-08.
  - The opencode v2 check matches `(^|\s)v?2\.` against `opencode --version` ("opencode v2.2.6"). The bash version's unanchored `v?2\.` also matched v1 releases such as `v1.12.0`. Fixed 2026-11-08.
  - Sudo keep-alive: `sudo -v`, then a background `bash -c 'while kill -0 <pwsh PID> 2>/dev/null; do sudo -n true; sleep 60; done'` started with `Start-Process` (builder's choice if another approach is simpler); skipped in dry-run.

- [x] **Step 1: Write the failing tests**

  `tests/Tools.Tests.ps1`: the five GitKraken cases from `tests/gitkraken.test.sh` (same inputs and expectations), plus `Get-LatestNodeLts returns the last line's version` with a fake `fnm` printing `v24.22.2 (Krypton)` / `v26.13.0 (Lithium)` → `v26.13.0`, and `Get-FnmDefault reads the default alias` with a fake `fnm list` printing `* v24.16.0` / `* v26.13.0 default` → `v26.13.0`.

  `tests/Setup.Tests.ps1` (fake `herdr` on `PATH` that prints a given status and logs calls):

  | Test | Assert |
  |---|---|
  | `skips when herdr is current and the hook is in settings` | status `claude: current (v11)`; settings contains `herdr-agent-state.sh` → no `install` call; `-` line |
  | `reinstalls when the settings file lacks the hook` | status current; settings without it → `integration install claude` logged |
  | `installs when herdr reports not installed` | status `claude: not installed` → install logged |
  | `opencode: skips when current and cli.json references herdr` | status `opencode: current (v13)`; `cli.json` contains `herdr-opencode` → no install call |
  | `opencode: installs when cli.json lacks the herdr plugin` | status current; `cli.json` without it → `integration install opencode` logged |
  | `skips an agent that isn't installed` | no fake `opencode` on `PATH` → `-` line for opencode, no install call |
  | `skips when herdr is missing` | no `herdr` on `PATH` → `-` line |

- [x] **Step 2: Run the tests to verify they fail**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests/Tools.Tests.ps1, tests/Setup.Tests.ps1 -Output Detailed'`
  Expected: all fail.

- [x] **Step 3: Implement the modules, `install.ps1`, `update.ps1`; edit `settings.json` and `bootstrap.sh`**

- [x] **Step 4: Run the tests to verify they pass**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests -Output Detailed'`
  Expected: all passed, 0 failed.

- [x] **Step 5: Dry-run both scripts on this machine**

  ```bash
  pwsh -NoProfile ./install.ps1 -WhatIf   # expect: retire block as Task 6 Step 5; same tool steps as ./install.sh --dry-run (minus stow); "~" lines for sync; setup actions block
  pwsh -NoProfile ./update.ps1 -WhatIf    # expect: retire block; same update steps as ./update.sh --dry-run; sync dry-run; setup actions block; exit 0
  ./install.sh --dry-run >/tmp/sh.txt; pwsh -NoProfile ./install.ps1 -WhatIf >/tmp/ps.txt; diff <(grep '^•' /tmp/sh.txt) <(grep '^•' /tmp/ps.txt)   # expect: only the stow/sync/setup/retire status lines differ
  ```

- [ ] **Step 6: Checkpoint: user reviews and commits** (suggested: `port install and update scripts to PowerShell`)

---

### Task 8: herdr-core and sshd for the Windows Herdr app

The Herdr desktop app on Windows manages agents in WSL by treating the distro as an SSH machine. That needs herdr-core in the distro and an sshd that Windows reaches on `127.0.0.1:2222`. This was set up by hand and tested on 2026-11-08 (agent status, notifications, and reconnecting after `wsl --shutdown` all worked); this task makes it repeatable. The herdr TUI stays installed and integrated: nothing here removes it.

**Files:**
- Create: `linux/sshd_config.d/herdr-wsl.conf`
- Modify: `lib/Tools.psm1`, `lib/Setup.psm1`, `install.ps1`, `update.ps1`, `tests/Setup.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 1, 7.
- Produces, in `lib/Tools.psm1`:
  - `Test-Wsl` → `[bool]`: `/proc/sys/fs/binfmt_misc/WSLInterop` exists. Not `$env:WSL_DISTRO_NAME`, which SSH sessions don't have.
  - `Get-HerdrCorePath` → `[string]`, `<home>/.local/bin/herdr-core`. Steps call this path, not `hc`, because the installer only creates the `hc` link when no other `hc` is on `PATH`.
- Produces, in `lib/Setup.psm1`:
  - `Invoke-WslSshd [string]$ConfigDir = '/etc/ssh/sshd_config.d', [string]$SshdPath = '/usr/sbin/sshd'` (parameters for tests):
    1. Not WSL → `Write-Skip "Not WSL — skipping sshd for the Herdr app"`.
    2. `$SshdPath` missing → `Write-Warn "openssh-server isn't installed — run ./install.ps1"`, return.
    3. `<ConfigDir>/herdr-wsl.conf` equals the repo file, and `systemctl is-enabled ssh` prints `enabled` and `systemctl is-active ssh` prints `active` → `Write-Skip "sshd for the Herdr app is already set up"`.
    4. Otherwise, in order: `Invoke-Step "sudo install -m 644 <repo>/linux/sshd_config.d/herdr-wsl.conf <ConfigDir>/herdr-wsl.conf"`, `sudo sshd -t`, `sudo systemctl enable ssh`, `sudo systemctl restart ssh`. If one fails, the rest aren't run (a config that fails `sshd -t` is never loaded), and instead of throwing it prints `Write-Warn "sshd setup failed — check 'sudo journalctl -u ssh -n 20'; port 2222 may be used by another WSL distro (they share one network)"` and returns, so install and update carry on.
    5. Then, if `<home>/.ssh/authorized_keys` is missing or has no line starting `ssh-`, `Write-Warn "No keys in ~/.ssh/authorized_keys — add the Windows key (see windows/README.md)"`.
  - `Invoke-SetupActions` calls `Invoke-WslSshd` after the herdr integrations.
- `linux/sshd_config.d/herdr-wsl.conf` (not in the manifest: its target is outside home, and only the setup action writes it):

  ```
  # Lets the Windows Herdr app reach this WSL distro over SSH: key login only, localhost only
  Port 2222
  ListenAddress 127.0.0.1
  PasswordAuthentication no
  KbdInteractiveAuthentication no
  PermitRootLogin no
  ```

  No `AllowUsers` line: the username differs between machines, and key-only login on localhost is enough.
- `install.ps1`: `openssh-server` joins the apt packages only when `Test-Wsl`. New step after herdr: `Write-Status "Installing herdr-core..."`, skip if `Get-HerdrCorePath` exists, else `Invoke-Step 'curl -fsSL https://releases.herdr.dev/core/install.sh | sh'`. On every Linux machine, not just WSL: any of them can be added as a machine in the app.
- `update.ps1`: new step after herdr: `Write-Status "Updating herdr-core..."`, skip if `Get-HerdrCorePath` is missing, else `Invoke-Step "<herdr-core path> update"` (running terminals keep running).

- [x] **Step 1: Write the failing tests** in `tests/Setup.Tests.ps1` (`Mock Test-Wsl -ModuleName Setup`; fake `sudo` and `systemctl` on `PATH` that log calls, with a configurable failing command; temp `ConfigDir`; a temp file as `SshdPath`)

  | Test | Assert |
  |---|---|
  | `sshd: skips when not WSL` | no `sudo` calls; `-` line |
  | `sshd: warns when openssh-server is missing` | `SshdPath` absent → `!` line; no `sudo` calls |
  | `sshd: skips when the config matches and ssh is running` | `ConfigDir` holds the repo file; `systemctl` prints `enabled` / `active` → no `sudo` calls; `-` line |
  | `sshd: installs the config and restarts ssh when it differs` | logged in order: `install -m 644`, `sshd -t`, `systemctl enable ssh`, `systemctl restart ssh` |
  | `sshd: doesn't restart when sshd -t fails` | `sshd -t` fails → no `restart` logged; `!` line; no throw |
  | `sshd: a failed restart warns and doesn't throw` | `restart` fails → `!` line containing `2222` |
  | `sshd: warns when authorized_keys has no key` | empty `<home>/.ssh/authorized_keys` → `!` line containing `authorized_keys` |
  | `sshd: -WhatIf changes nothing` | no `sudo` calls; `~` lines |

- [x] **Step 2: Run the tests to verify they fail**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests/Setup.Tests.ps1 -Output Detailed'`
  Expected: the 8 new tests fail; Task 7's still pass.

- [x] **Step 3: Write `herdr-wsl.conf`; implement `Test-Wsl`, `Get-HerdrCorePath`, `Invoke-WslSshd` and the install/update steps**

- [x] **Step 4: Run the tests to verify they pass**

  Run: `pwsh -NoProfile -c 'Invoke-Pester tests -Output Detailed'`
  Expected: all passed, 0 failed.

- [x] **Step 5: Dry-run both scripts on this machine**

  ```bash
  pwsh -NoProfile ./install.ps1 -WhatIf   # expect: openssh-server in the apt list; "Installing herdr-core..." then a "-" line (already installed); setup actions end with the four "~ sudo ..." sshd lines (the trial's file has a different name)
  pwsh -NoProfile ./update.ps1 -WhatIf    # expect: "~ /home/meeg/.local/bin/herdr-core update"; the same sshd lines; exit 0
  ```

- [ ] **Step 6: Checkpoint: user reviews and commits** (suggested: `install herdr-core and sshd for the Windows Herdr app`)

---

### Task 9: Migrate this machine, remove the bash scripts, update docs

**Files:**
- Delete: `install.sh`, `update.sh`, `lib/retire.sh`, `lib/gitkraken.sh`, `tests/retire.test.sh`, `tests/gitkraken.test.sh`, `claude/.stow-local-ignore`, `opencode/.stow-local-ignore`
- Modify: `AGENTS.md`, `linux/README.md`, `claude/README.md`, `opencode/.config/opencode/README.md`, `README.md`, `docs/superpowers/plans/2026-10-27-chezmoi-migration.md` (superseded note at the top), `.editorconfig` if it lists `.sh` scripts only

**Interfaces:** none.

- [x] **Step 1: Migrate this machine (user)**

  Commit and push pending dotfile changes first, discarding tool-injected entries (GitKraken's in `claude/.claude/settings.json`). Delete the trial's sshd file, which the repo's `herdr-wsl.conf` replaces with the same settings: `sudo rm /etc/ssh/sshd_config.d/herdr-trial.conf` (sshd keeps running on the old settings until the setup action restarts it). Then run `pwsh ./install.ps1`.
  Expected: retire replaces every stow link with a real file and removes stow; tools skip as installed; sync records state; setup actions reinstall herdr's Claude hook into the live `~/.claude/settings.json`, report opencode's integration as current, and install `herdr-wsl.conf` and restart sshd; GitKraken re-adds its entries when next started.

- [x] **Step 2: Verify**

  ```bash
  find ~ -maxdepth 1 -lname '*.dotfiles/*'; find ~/.config ~/.claude -lname '*.dotfiles/*'   # expect: no output
  ls ~/.local/state/dotfiles/applied/.bashrc                                               # expect: exists
  grep -c herdr-agent-state.sh ~/.claude/settings.json                                     # expect: 1
  grep -c herdr-agent-state.sh ~/.dotfiles/claude/.claude/settings.json                    # expect: 0
  herdr integration status | grep -E '^(claude|opencode):'                                  # expect: both "current"
  pwsh -NoProfile ./sync.ps1 -NoPull -NoPrompt                                             # expect: exit 0; only tool-injected local changes (settings.json: herdr hook, GitKraken entries; possibly opencode's cli.json)
  ls /etc/ssh/sshd_config.d/                                                               # expect: herdr-wsl.conf only
  ss -ltn | grep '127.0.0.1:2222'                                                          # expect: one LISTEN line
  ```

  Then, in the Windows Herdr app: the `wsl` machine shows as connected and an agent started on it reports working and done.

- [x] **Step 3: Try copy-back interactively (user)**

  Change a setting in Claude Code (e.g. toggle a plugin), run `pwsh ./sync.ps1 -NoPull`, choose `c` for `settings.json`, then `git diff` in the repo: the change is there, the herdr/GitKraken lines are too (as `@HOME@` paths) — stage only the change with `git add -p` and discard the rest. (The interactive prompt and the VS Code merge/diff paths aren't covered by the automated tests; this step is their check.)

- [x] **Step 4: Remove the bash scripts and stow files; update docs**

  Docs per the spec's "Docs" section: `AGENTS.md` (conventions: dotfile management via `dotfiles.json` + `sync.ps1`; key commands: `./bootstrap.sh`, `pwsh ./install.ps1`, `pwsh ./update.ps1`, `pwsh ./sync.ps1 [-NoPull] [-NoPrompt] [-CopyBack] [-WhatIf]`, `pwsh ./retire.ps1 -WhatIf`, `pwsh -c 'Invoke-Pester tests'`; "Working on This Repo": add a file by adding a manifest entry; how to remove a tool; `@HOME@` and "quote it in YAML"); `linux/README.md` (bootstrap instead of stow; "Migrating a stow machine" section: commit/push, discard tool-injected entries, `git pull --autostash`, `./bootstrap.sh`); `claude/README.md` and the opencode README (sync and copy-back instead of stow/adopt; in `claude/README.md`, the "Local plugins" section's "Stow skips the folder (`claude/.stow-local-ignore`)" sentence becomes "the manifest doesn't list the folder", and the "Dotfiles" and "Global instructions" sections say the files are copied by sync rather than linked). Mark the chezmoi plan superseded by the design doc.

  Herdr app docs (Task 8): the manual steps were written on 2026-11-08 in `linux/README.md` ("herdr app (Windows) → WSL") and `windows/README.md` ("herdr app"). In the Linux section, replace the herdr-core and sshd steps with "install.ps1 and update.ps1 do this on WSL" and point at `linux/sshd_config.d/herdr-wsl.conf` instead of the inline copy; keep the authorised-key step manual, and keep the port-2222 and "TUI stays alongside" notes. Leave the Windows section as it is: it stays manual until Stage 3.

- [x] **Step 5: Verify**

  ```bash
  grep -rn -i -E '\bstow\b|install\.sh|update\.sh' --include=*.md . | grep -v docs/superpowers   # expect: only the "Migrating a stow machine" section
  pwsh -NoProfile -c 'Invoke-Pester tests -Output Detailed'                                       # expect: all passed
  pwsh -NoProfile ./update.ps1 -WhatIf                                                            # expect: exit 0, retire block all "-" lines
  ```

- [ ] **Step 6: Checkpoint: user reviews and commits** (suggested: `switch to PowerShell sync and retire stow`)

---

### Task 10: End-to-end check on a throwaway WSL distro (user)

**Files:** none (fix anything it finds in the owning task's files).

- [ ] **Step 1: Fresh install**

  From PowerShell on Windows: `wsl --install -d Debian --name dotfiles-test`. Inside: `sudo apt install -y git && git clone https://github.com/cmeagher-rwy/dotfiles.git ~/.dotfiles && cd ~/.dotfiles && ./bootstrap.sh`.
  Expected: pwsh installed; tools installed, including herdr-core (`~/.local/bin/herdr-core --version`); `herdr integration status` shows claude and opencode current; the sshd setup action warns that it failed, because the main Debian distro already holds port 2222 (WSL distros share one network), and the install carries on to "Done"; Debian's default `~/.bashrc` backed up under `~/.local/state/dotfiles/backup/` and replaced; `ls -l ~/.bashrc` shows a regular file; a second `pwsh ./sync.ps1 -NoPull -NoPrompt` reports nothing to write.

- [ ] **Step 2: Stow-machine migration**

  In the same distro: remove the files sync wrote and the state folder; `git checkout <commit before Stage 1>`; `./install.sh` (old bash, stows everything); `git checkout main`; `./bootstrap.sh`.
  Expected: no links into `~/.dotfiles` remain; stow is removed; herdr's Claude and opencode integrations are both current; a second sync reports only the expected local-only entries.

- [ ] **Step 3: Clean up**

  From PowerShell: `wsl --unregister dotfiles-test`.

- [ ] **Step 4: Checkpoint: user reviews and commits any fixes**

---

## Addenda: deferred items

- **Repo location is hard-coded in agent config** (deferred 2026-11-08). `CLAUDE_CODE_PLUGIN_DIRS` in `claude/.claude/settings.json` (`~/.dotfiles/claude/.claude/local-plugins`) and the `skills` list in `opencode/.config/opencode/opencode.jsonc` (`~/.dotfiles/claude/.claude/local-plugins/<plugin>/skills`) assume the repo is at `~/.dotfiles`, while the scripts allow another location through `DOTFILES_REPO`. On a machine with the repo elsewhere, the local plugins and their skills wouldn't load. Possible fixes: a second placeholder (e.g. `@DOTFILES@`, filled in by sync like `@HOME@`), or documenting that the repo must live at `~/.dotfiles`.
- **Nothing installs Pester on other machines** (raised 2026-11-08, Task 1). Task 1 installed Pester 6 on this machine by hand, but no script or doc does it elsewhere, while Task 9 documents `pwsh -c 'Invoke-Pester tests'` as a key command. Fix: in Task 9's `AGENTS.md` update, add the install command (`Install-Module Pester -MinimumVersion 6.0 -Scope CurrentUser -Force`) beside the test command. **Done 2026-11-08** in Task 9: `AGENTS.md`'s Key Commands table has it beside the test command.

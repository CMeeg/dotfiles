# AGENTS.md

This repository contains dotfiles, setup scripts, and reference configs for setting up **Windows 11**, **WSL 2**, and **Linux (Debian on WSL)**.

## Conventions

- **Shell**: Bash (`.bashrc` is primary config)
- **Prompt**: Starship with Dracula theme (`starship/.config/starship.toml`)
- **Package managers**: `apt` (Debian), `winget`/`choco` (Windows)
- **Dotfile management**: `dotfiles.json` lists every managed file and where it goes; `sync.ps1` copies them into place as real files and syncs changes both ways
- **Scripts**: PowerShell 7 (`pwsh`) for `install.ps1`, `update.ps1`, `sync.ps1` and `retire.ps1`, with shared modules in `lib/`; bash only for `bootstrap.sh`, which installs PowerShell
- **Theme**: Dracula throughout
- **Font**: JetBrains Mono / JetBrainsMono Nerd Font
- **File style**:
  - 2-space indent for JSON, JSONC, YAML, TOML, Shell, PowerShell
  - 4-space indent for `.gitconfig`
  - Shell scripts: `set -euo pipefail`, use `#!/usr/bin/env bash`
  - PowerShell scripts and modules: start with `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`
  - Markdown: no hard-wrapping — keep paragraphs (and long bullets) on single lines and let the editor wrap instead
- **Secrets**: Place private env vars in `~/.secrets` (gitignored)
- **Editor**: VS Code (`code --wait`) as core editor and git editor

## Key Commands

| Command | Description |
|---------|-------------|
| `./bootstrap.sh` | Install PowerShell 7 if it's missing, then run `install.ps1` (arguments pass through, e.g. `-WhatIf`) |
| `pwsh ./install.ps1 [-WhatIf] [-SkipRetire]` | Run the retire steps, install the tools, apply the dotfiles and run the setup actions |
| `pwsh ./update.ps1 [-WhatIf] [-SkipRetire]` | Run the retire steps, update the tools, pull and sync the dotfiles and run the setup actions |
| `pwsh ./sync.ps1 [-NoPull] [-NoPrompt] [-CopyBack] [-WhatIf]` | Pull the repo, apply it to this machine and report local changes, offering to copy each one back into the repo |
| `pwsh ./retire.ps1 -WhatIf` | Preview removing retired tools and leftover stow links |
| `pwsh -c 'Invoke-Pester tests'` | Run the tests. Install Pester once with `pwsh -c 'Install-Module Pester -MinimumVersion 6.0 -Scope CurrentUser -Force'` |

## Working on This Repo

- To add a dotfile, put it in the repo at the same relative path it has under `$HOME`, inside a folder named for its tool (e.g. `herdr/.config/herdr/config.toml`), and add an entry to `dotfiles.json` with its `source` and `linux` target. Then run `pwsh ./sync.ps1 -NoPull`. An entry whose source is a folder manages every file under it; files other tools add there show up as new local files until excluded with an `exclude` glob.
- Folders not listed in `dotfiles.json` (e.g. `windows/`, `wsl/`, `vscode/`) are reference configs and docs.
- Where a file needs the machine's home path, write `@HOME@`. Sync fills it in when applying and puts it back when copying back. In YAML, quote a value that starts with `@HOME@`, as `@` can't start a plain value.
- The repo holds the intended settings and each machine has real copies. Sync reads the repo's working tree, so `pwsh ./sync.ps1 -NoPull` tries out uncommitted edits. It never commits or pushes: after copying back, review with `git diff` and stage what you want.
- Tools write machine-specific entries into some live files (herdr's hook and GitKraken's marketplace in `~/.claude/settings.json`). They stay local: skip them when copying back, or discard them from the repo afterwards.
- Sync keeps a last-applied copy of each file in `~/.local/state/dotfiles/applied/` and backups in `~/.local/state/dotfiles/backup/`. Deleting the folder resets tracking.
- To remove a tool, delete its steps from `install.ps1` and `update.ps1`, its entries from `dotfiles.json` and its files from the repo, then add a retire step to `lib/Retire.psm1` and call it from `Invoke-RetireSteps`. A retire step only removes, never installs, and prints one `-` line when there's nothing to remove.
- `-WhatIf` must change nothing. Each script turns it into `Set-DryRun` and then sets `$WhatIfPreference = $false`; commands that change things go through `Invoke-Step`, and file writes through helpers that check the dry-run flag.
- Tests are Pester tests in `tests/`. Tests that would run `sudo`, `apt` or an installed tool (herdr, dotnet, systemctl, …) put fakes first on `PATH` so the real ones are never called; the sync tests run real `git` in temp folders.
- Only commit hand-written Claude Code config under `claude/.claude/` (settings, `local-plugins/`, skills, `CLAUDE.md`, etc.) — never credentials, history, sessions, or plugin caches. `.gitignore` allowlists the safe paths. `claude/.claude/local-plugins` isn't in `dotfiles.json`: Claude Code and opencode load it straight from the repo.

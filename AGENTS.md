# AGENTS.md

This repository contains dotfiles, setup scripts, and reference configs for setting up **Windows 11**, **WSL 2**, and **Linux (Debian on WSL)**.

## Directory Layout

### Stow packages (managed with GNU Stow)
These directories are symlinked into `$HOME` using `stow --adopt -v <package>`:

| Directory | Contents |
|-----------|----------|
| `bash/` | `.bashrc`, `.bash_aliases`, `.bash_logout`, `.profile` |
| `git/` | `.gitconfig` |
| `starship/` | `.config/starship.toml` — Starship prompt theme (Dracula) |
| `agents/` | `.agents/skills/` — opencode agent skill definitions |
| `opencode/` | `.config/opencode/` — opencode config (MCP servers, TUI theme) |

### Setup guides
| Directory | Contents |
|-----------|----------|
| `linux/` | Debian setup guide |
| `windows/` | Windows 11 setup guide |
| `wsl/` | WSL 2 `.wslconfig` and setup guide |
| `gitkraken/` | GitKraken setup guide |

### Reference configs
These files are not stowed but serve as reference for manual configuration:

| Directory | Contents |
|-----------|----------|
| `powershell/` | PowerShell profile + oh-my-posh theme (Windows) |
| `vscode/` | VS Code `settings.json` reference |
| `windows-terminal/` | Windows Terminal `settings.json` reference |

## Conventions

- **Shell**: Bash (`.bashrc` is primary config)
- **Prompt**: Starship with Dracula theme (`starship/.config/starship.toml`)
- **Package managers**: `apt` (Debian), `winget`/`choco` (Windows)
- **Dotfile management**: GNU Stow with `--adopt` flag
- **Theme**: Dracula throughout
- **Font**: JetBrains Mono / JetBrainsMono Nerd Font
- **File style**:
  - 2-space indent for JSON, JSONC, YAML, TOML, Shell
  - 4-space indent for `.gitconfig`
  - Shell scripts: `set -euo pipefail`, use `#!/usr/bin/env bash`
- **Secrets**: Place private env vars in `~/.secrets` (gitignored)
- **Editor**: VS Code (`code --wait`) as core editor and git editor

## Key Commands

| Command | Description |
|---------|-------------|
| `stow --adopt --no-folding -v bash git starship` | Link shell, git, and starship dotfiles |
| `stow --adopt --no-folding -v agents opencode` | Link opencode config and agent skills |
| `./install.sh` | Automated Debian setup (idempotent) |
| `./install.sh --dry-run` | Preview what the installer would do |
| `source ~/.bashrc` | Reload bash configuration |

## Working on This Repo

- Before running stow on a system that already has dotfiles, `--adopt` moves
  existing target files into the stow directory. Review with `git diff` afterwards.
- `.stow-local-ignore` tells stow to skip `.git`, `.DS_Store`, and `README.md`.
- The `install.sh` script is idempotent and supports `--dry-run`.
- Not every directory is a stow package — only `bash/`, `git/`, `starship/`, `agents/`, and
  `opencode/` are managed with stow.
- When adding new dotfiles, create them inside the appropriate stow package
  directory using the same relative path as they would have in `$HOME`.

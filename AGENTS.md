# AGENTS.md

This repository contains dotfiles, setup scripts, and reference configs for setting up **Windows 11**, **WSL 2**, and **Linux (Debian on WSL)**.

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
  - Markdown: no hard-wrapping — keep paragraphs (and long bullets) on single lines and let the editor wrap instead
- **Secrets**: Place private env vars in `~/.secrets` (gitignored)
- **Editor**: VS Code (`code --wait`) as core editor and git editor

## Key Commands

| Command | Description |
|---------|-------------|
| `stow --adopt --no-folding -v bash git starship superfile herdr` | Link shell, git, starship, superfile, and herdr dotfiles |
| `stow --adopt --no-folding -v agents opencode` | Link opencode config and agent skills |
| `stow --adopt --no-folding -v claude` | Link Claude Code settings, mods, and skills |

## Working on This Repo

- Before running stow on a system that already has dotfiles, `--adopt` moves
  existing target files into the stow directory. Review with `git diff` afterwards.
- `.stow-local-ignore` tells stow to skip `.git`, `.DS_Store`, and `README.md`.
- The `install.sh` script is idempotent and supports `--dry-run`.
- Not every directory is a stow package — only `bash/`, `git/`, `starship/`, `superfile/`, `herdr/`, `agents/`,
  `opencode/`, and `claude/` are managed with stow.
- Only commit hand-written Claude Code config under `claude/.claude/` (settings, mods, skills, `CLAUDE.md`, etc.) — never credentials, history, sessions, or plugin caches. `.gitignore` allowlists the safe paths. Always stow `claude` with `--no-folding` so `~/.claude` stays a real directory.
- When adding new dotfiles, create them inside the appropriate stow package
  directory using the same relative path as they would have in `$HOME`.

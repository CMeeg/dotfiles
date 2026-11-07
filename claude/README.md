# Claude

## Claude Code

[Claude Code](https://code.claude.com/docs/en/quickstart) is Anthropic's terminal-based AI coding agent.

### Linux / WSL

* Install (native install — recommended)
  * `curl -fsSL https://claude.ai/install.sh | bash`
  * `reload` - reload bash (using alias)
  * `claude --version` - verify the install
* Run `claude` and follow the prompts to sign in

### Windows

* Install [Git for Windows](https://git-scm.com/downloads/win) first (recommended)
  * `winget install --id Git.Git`
  * With it, Claude Code can use its Bash tool. Without it, Claude Code falls back to PowerShell.
* Install Claude Code (PowerShell, not admin)
  * `irm https://claude.ai/install.ps1 | iex`
  * If the installer warns that `%USERPROFILE%\.local\bin` isn't on your `PATH`, add it to your user `PATH` (Settings → System → About → Advanced system settings → Environment Variables)
  * Open a new terminal and run `claude --version` to verify
* Install Python and make sure `python` is on `PATH` (see [Tips](#tips))
  * `winget install --id Python.Python.3.13`
* Run `claude` from a project folder and follow the prompts to sign in
* Run `claude doctor` to check the install

#### Windows and WSL side by side

The Windows install runs side by side with the WSL one. They don't clash because each keeps everything in its own home directory:

| | WSL | Windows |
|---|---|---|
| Binary | `~/.local/bin/claude` | `%USERPROFILE%\.local\bin\claude.exe` |
| Settings, skills, plugins, sessions | `~/.claude/` | `%USERPROFILE%\.claude\` |
| Login + user-scope MCP servers | `~/.claude.json` | `%USERPROFILE%\.claude.json` |

Ground rules for keeping them separate:

* Use each install for files on its own filesystem. Don't run Windows Claude against `\\wsl$\...` paths, or WSL Claude against `/mnt/c/...`. Access across the boundary is slow, and git and line endings tend to misbehave.
* Don't share one config directory between them. Don't symlink `%USERPROFILE%\.claude` into WSL, and don't point `CLAUDE_CONFIG_DIR` at the other side. Sessions, plugin caches and credentials use OS-specific paths and get corrupted if both installs write to them.
* Each install auto-updates on its own and needs its own sign-in. Plugins and settings also have to be set up separately.
* VS Code picks the install that matches the window: a Remote-WSL window uses the WSL install, and a local window uses the Windows one.
* WSL appends the Windows `PATH`, so `claude.exe` is visible from WSL, but bash only matches the exact name `claude`. Typing `claude` in WSL still runs the Linux binary, which you can confirm with `which -a claude`.

### Settings

Stow isn't available on Windows, so set up the config by hand.

* Clone the dotfiles repo to `%USERPROFILE%\.dotfiles` on Windows as well, so `~/.dotfiles` is the same path on both. You can reach the WSL copy from Windows at `\\wsl.localhost\Debian\home\chrism\.dotfiles`.
* Don't copy `claude/.claude/settings.json` as it is. Some of its settings are specific to one OS or one project:
  * `hooks`: hooks often run OS-specific commands, so set them up on each OS instead of copying them. For example, the `SessionStart` hook comes from [herdr](https://herdr.dev). Run `herdr integration install claude` and it adds a hook that suits the OS (a bash script in WSL, a PowerShell script on Windows).
  * `extraKnownMarketplaces` and `enabledPlugins`: some marketplaces and plugins are only there because one project needed them. Add those when you work on that project.
* Instead, create `%USERPROFILE%\.claude\settings.json` with the settings that work on both:

  ```json
  {
    "permissions": {
      "defaultMode": "auto"
    },
    "respectGitignore": false,
    "awaySummaryEnabled": false,
    "askUserQuestionTimeout": "never",
    "env": {
      "CLAUDE_CODE_PLUGIN_DIRS": "~/.dotfiles/claude/.claude/mods"
    }
  }
  ```

* Leave out `theme`, `extraKnownMarketplaces`, `enabledPlugins` and `pluginConfigs` for now. Installing the theme and plugins below adds those settings for you.
* Copy the skills you want from `claude/.claude/skills/` into `%USERPROFILE%\.claude\skills\`
  * These are copies, so re-copy them after you change a skill in the repo
* Local mods need no copying, because `CLAUDE_CODE_PLUGIN_DIRS` loads them straight from the repo clone. `git pull` picks up changes.
* Then follow the [Theme](#theme), [Config](#config), [Plugins](#plugins) and [Mods](#mods) steps below, the same as on Linux.

### Dotfiles

`claude/` is a stow package — `claude/.claude/` is linked into `~/.claude`:

* Claude Code rewrites `settings.json` when you change settings or install plugins — if `ls -l ~/.claude/settings.json` shows it's no longer a symlink, re-run the stow command to adopt the changes back into the repo

### Theme

* Install [Dracula theme](https://github.com/matcra587/claude-themes)
* Restart Claude Code
* Select Dracula `/theme`

### Config

These are config settings I have changed from the default:

* Default permission mode: `Auto`
* Respect .gitignore in file picker: `false`
* Session recap: `false`
* Question auto-continue timeout: `never`

### Plugins

Some plugins are project specific, but these are worth installing at user scope:

* [Chrome DevTools MCP](https://claude.com/marketplace/plugins/chrome-devtools-mcp)
* [Context7](https://claude.com/marketplace/connectors/context7)
* [Superpowers](https://claude.com/marketplace/plugins/superpowers)

If Context7 has been added to your claude.ai account, Claude Code installs it for you and `/plugin` shows it as `synced`. In that case you don't need to install it again.

### Skills

Personal skills live in `claude/.claude/skills/<name>/` and are linked into `~/.claude/skills/`. opencode reads `~/.claude/skills` too, so these skills work in both tools:

* New skill — create it in `claude/.claude/skills/<name>/SKILL.md`, then run `stow --no-folding -v claude` (from the dotfiles root)
* Existing skill already in `~/.claude/skills/<name>/` — copy it into `claude/.claude/skills/<name>/`, then run `stow --adopt --no-folding -v claude` to replace the original with a symlink
* `~/.claude/skills/synced/` holds skills Claude Code syncs down from claude.ai — it's managed by Claude Code, so it's gitignored and not part of the stow package

### Mods

Under the hood, mods are plugins too. Here, "mods" means plugins that change Claude Code's interface (status line, footer, panels), and "plugins" means everything else (skills, agents, MCP servers).

#### Local mods

These are my own mods. They live in `claude/.claude/mods/<name>/`:

* `model-effort-status`: shows the current model and reasoning effort at the bottom right of the prompt footer

Claude Code loads them straight from the repo through `env.CLAUDE_CODE_PLUGIN_DIRS` (`~/.dotfiles/claude/.claude/mods`). That path is the same on Linux and Windows, so edits land in the repo with no copying. Stow also links them into `~/.claude/mods/`, but Claude Code doesn't load them from there.

#### Marketplace mods

These are installed from the [statuslin.es](https://statuslin.es) marketplace (`statuslines` in `settings.json`):

* [Context Bar](https://statuslin.es/mods/context-bar)
* [Sub Meter](https://statuslin.es/mods/sub-meter)

### Tips

* `claude update` - apply an update immediately (reports the version change, or that you're already up to date)
  * Native installations also auto-update in the background, so `claude update` is only needed to update without waiting for the next background check
* Claude likes to use `python` when doing tasks like modifying files so it's worth making sure that is installed and on path

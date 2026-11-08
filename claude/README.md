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

`sync.ps1` doesn't manage Windows files yet, so set up the config by hand.

* Clone the dotfiles repo to `%USERPROFILE%\.dotfiles` on Windows as well, so `~/.dotfiles` is the same path on both. You can reach the WSL copy from Windows at `\\wsl.localhost\Debian\home\chrism\.dotfiles`.
* Don't copy `claude/.claude/settings.json` as it is. Some of its settings are specific to one OS or one project:
  * `hooks`: hooks often run OS-specific commands, so set them up on each OS instead of copying them. For example, the `SessionStart` hook comes from [herdr](https://herdr.dev). Run `herdr integration install claude` and it adds a hook that suits the OS (a bash script in WSL, a PowerShell script on Windows).
  * `extraKnownMarketplaces` and `enabledPlugins`: some marketplaces and plugins are only there because one project needed them. Add those when you work on that project.
* Instead, create `%USERPROFILE%\.claude\settings.json` with the [settings](#config) that work on both:
* Add `permissions.deny` from `claude/.claude/settings.json` as well (see [Secrets](#secrets)).
* Leave out `theme`, `extraKnownMarketplaces`, `enabledPlugins` and `pluginConfigs` for now. Installing the theme and plugins below adds those settings for you.
* Copy `claude/.claude/CLAUDE.md` (the global instructions, see [Global instructions](#global-instructions)) to `%USERPROFILE%\.claude\CLAUDE.md`
  * It's a copy, so re-copy it after you change `CLAUDE.md` in the repo
* Skills need no copying: they're all in local plugins, which `CLAUDE_CODE_PLUGIN_DIRS` loads straight from the repo clone. `git pull` picks up changes.
* Then follow the [Theme](#theme), [Config](#config), [Plugins](#plugins) and [Local plugins](#local-plugins) steps below, the same as on Linux.

### Dotfiles

`claude/.claude/settings.json` and `claude/.claude/CLAUDE.md` are copied to `~/.claude/` by `sync.ps1` (they're listed in `dotfiles.json`), which `install.ps1` and `update.ps1` run:

* Claude Code rewrites `~/.claude/settings.json` when you change settings or install plugins. The next `pwsh ./sync.ps1` shows the change and offers to copy it back into the repo (see [Syncing dotfiles](../linux/README.md#syncing-dotfiles)).
* herdr's `SessionStart` hook and GitKraken's marketplace and plugin entries are written into the live file by those tools, so they aren't in the repo and show up as local changes on every sync. Skip them, or discard them from the repo after copying back. The installer's setup actions run `herdr integration install claude` when the hook is missing.

### Global instructions

`claude/.claude/CLAUDE.md` is copied to `~/.claude/CLAUDE.md` by sync: my working preferences for every repository (git, processes, scope and follow-ups, writing code, verifying, communicating, secrets), which a repository's own `AGENTS.md` or `CLAUDE.md` adds to. opencode reads it too when it has no `~/.config/opencode/AGENTS.md`.

### Secrets

`permissions.deny` in `settings.json` stops Claude Code reading files that hold secrets in any project:

* `.env.local` and `.env.*.local`
* `.secrets`
* `local.settings.json`
* keys and certificates (`*.pem`, `*.key`, `*.pfx`, `*.p12`, `~/.ssh/id_*`)
* the credential files in the home folder (`.netrc`, `.git-credentials`, `.pgpass`, AWS, Docker, GitHub CLI, Claude Code's own)

The rules cover the Read and Grep tools and Bash commands that name the file (`cat`, `head`, `grep`), subagents included; checking a variable is set (`[ -n "$(grep '^NAME=' .env.local)" ] && echo set`) still works.

They don't cover a script that opens the file itself (e.g. `node -e "…readFileSync('.env.local')"`), which only [sandboxing](https://code.claude.com/docs/en/sandboxing) would.

A committed `.env` stays readable, so a project that keeps secrets in an uncommitted `.env` or `.env.production` needs its own rule in its `.claude/settings.local.json`.

### Theme

* Install [Dracula theme](https://github.com/matcra587/claude-themes)
* Restart Claude Code
* Select Dracula `/theme`

### Config

These are config settings I have changed from the default:


```jsonc
{
  "permissions": {
    "defaultMode": "auto" // This is Claude's recommendation and does seem to work well
  },
  "respectGitignore": false, // It's sometimes useful to be able to reference gitignored files
  "awaySummaryEnabled": false, // The recaps seemed too eager to display for me and you can always ask for a `/recap`
  "askUserQuestionTimeout": "never", // If a question is asked then I want to see it!
  "feedbackDrafts": "quiet", // The feedback "notice" can get in the way so this shows there is feedback to give in the footer instead that you can access with `/feedback`
  "env": {
    "CLAUDE_CODE_PLUGIN_DIRS": "~/.dotfiles/claude/.claude/local-plugins" // My local plugins from this repo
  }
}
```

### Plugins

Some plugins are project specific, but these are worth installing at user scope:

* [Chrome DevTools MCP](https://claude.com/marketplace/plugins/chrome-devtools-mcp)
* [Context7](https://claude.com/marketplace/connectors/context7)
* [Superpowers](https://claude.com/marketplace/plugins/superpowers)

If Context7 has been added to your claude.ai account, Claude Code installs it for you and `/plugin` shows it as `synced`. In that case you don't need to install it again.

### Skills

My skills are all in [local plugins](#local-plugins), grouped by when I'd reach for them. To add one, create `claude/.claude/local-plugins/<plugin>/skills/<name>/SKILL.md`; for a new plugin, add its `skills/` folder to `skills` in `opencode/.config/opencode/opencode.jsonc` too. `~/.claude/skills/synced/` holds skills Claude Code syncs down from claude.ai; it's managed by Claude Code and isn't in the repo.

### Local plugins

My own plugins live in `claude/.claude/local-plugins/<name>/`, each grouping related skills, hooks and mods (a mod is a plugin that changes Claude Code's interface, e.g. the status line, footer or panels).

Claude Code loads every plugin in that folder straight from the repo through `env.CLAUDE_CODE_PLUGIN_DIRS` (`~/.dotfiles/claude/.claude/local-plugins`), and calls their skills `<plugin>:<skill>` (e.g. `workflow:implement-plan`). That path is the same on Linux and Windows, so edits land in the repo with no copying.

The manifest (`dotfiles.json`) doesn't list the folder, so sync doesn't copy it into `~/.claude/`: Claude Code loads it from the repo instead. When Claude Code loads a plugin with a hooks module (e.g. a mod), it writes generated type files into the plugin's `.claude-plugin/types/`; that folder ignores itself in git.

### Marketplace mods

These are installed from the [statuslin.es](https://statuslin.es) marketplace (`statuslines` in `settings.json`):

* [Context Bar](https://statuslin.es/mods/context-bar)
* [Sub Meter](https://statuslin.es/mods/sub-meter)

### Tips

* `claude update` - apply an update immediately (reports the version change, or that you're already up to date)
  * Native installations also auto-update in the background, so `claude update` is only needed to update without waiting for the next background check
* Claude likes to use `python` when doing tasks like modifying files so it's worth making sure that is installed and on path

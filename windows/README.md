# windows

## windows setup

These setup instructions are for Windows 11.

* Install [Starship](https://starship.rs/)
  * `choco install starship`; or
  * `winget install --id Starship.Starship`
* Copy Starship config
  * `starship/.config/starship.toml` -> `~/.config/starship.toml`
* Install [jq](https://jqlang.org/) (coding agents use it to read JSON)
  * `winget install --id jqlang.jq`

### herdr

* Install [herdr](https://herdr.dev/tui/docs/install/) (PowerShell)
  * `powershell -ExecutionPolicy Bypass -c "irm https://herdr.dev/install.ps1 | iex"`
  * If endpoint security blocks that, run in Command Prompt: `curl.exe -fsSLo install.cmd https://herdr.dev/install.cmd && install.cmd && del install.cmd`
* Copy herdr config
  * `herdr/.config/herdr/config.toml` -> `%APPDATA%\herdr\config.toml`
* Update herdr
  * `herdr update`
  * Re-copy the config afterwards if it changed in the repo

### claude code

* See [Claude Code → Windows](../claude/README.md#windows). It runs alongside the WSL install without clashing.

### vscode

* Install extensions
  * `ms-vscode-remote.remote-wsl` - WSL

### opencode desktop

* [Download OpenCode Desktop](https://opencode.ai/download)
* Install the desktop app
* Run the server in wsl
  * `cd ~/ && opencode serve --port 4096`
* Open the desktop app
* Settings
  * General
    * Theme: Dracula
    * Code font: JetBrains Mono
  * Servers
    * Add server
      * Server address: http://localhost:4096
      * Server name: wsl

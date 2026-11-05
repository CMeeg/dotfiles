# windows

## windows setup

These setup instructions are for Windows 11.

* Install [Starship](https://starship.rs/)
  * `choco install starship`; or
  * `winget install --id Starship.Starship`
* Copy Starship config
  * `starship/.config/starship.toml` -> `~/.config/starship.toml`

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

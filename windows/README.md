# windows

## windows setup

These setup instructions are for Windows 11.

* Install [Starship](https://starship.rs/)
  * `choco install starship`; or
  * `winget install --id Starship.Starship`
* Copy Starship config
  * `starship/.config/starship.toml` -> `~/.config/starship.toml`

### herdr

* Install [herdr](https://herdr.dev/tui/docs/install/) (PowerShell)
  * `powershell -ExecutionPolicy Bypass -c "irm https://herdr.dev/install.ps1 | iex"`
  * If endpoint security blocks that, run in Command Prompt: `curl.exe -fsSLo install.cmd https://herdr.dev/install.cmd && install.cmd && del install.cmd`
* Copy herdr config
  * `herdr/.config/herdr/config.toml` -> `%APPDATA%\herdr\config.toml`
* Update herdr
  * `herdr update`
  * Re-copy the config afterwards if it changed in the repo

### herdr app

The [Herdr desktop app](https://herdr.dev/guide/) manages agents locally and in WSL (as an SSH machine). It runs alongside the herdr TUI above; both stay installed for now. Set up the WSL side first: [linux/README.md](../linux/README.md#herdr-app-windows--wsl).

* Install the app (it also installs herdr-core and then updates itself)
  * `powershell -c "irm https://releases.herdr.dev/app/install.ps1 | iex"`
* Create an SSH key just for WSL, with no passphrase (Herdr's background reconnects can't type one; the key only works against the localhost-only sshd in WSL)
  * From PowerShell 7: `ssh-keygen -t ed25519 -N '' -C windows-to-wsl-herdr -f $env:USERPROFILE\.ssh\id_ed25519_wsl`
  * Windows PowerShell 5 drops the empty `-N` argument and ssh-keygen waits for a passphrase, so use PowerShell 7 (or run `ssh-keygen.exe` from WSL)
  * Add `id_ed25519_wsl.pub` to WSL's `~/.ssh/authorized_keys` (see the linux steps)
* Add a `wsl` host to `%USERPROFILE%\.ssh\config`

  ```
  Host wsl
    HostName 127.0.0.1
    Port 2222
    User <WSL user>
    IdentityFile ~/.ssh/id_ed25519_wsl
    IdentitiesOnly yes
  ```

  * Use `127.0.0.1`, not `localhost`: Windows tries `::1` first and WSL only forwards IPv4, so herdr-core fails with `banner exchange: Connection to UNKNOWN port -1: Connection refused`
* Check `ssh wsl` logs in without a prompt (the first run trusts the host key)
* In the app, add a machine and pick `wsl` from the SSH config list
* After `wsl --shutdown`, the machine shows as unreachable and reconnects on its own once WSL is running again

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

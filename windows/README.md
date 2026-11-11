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

### herdr app

The [Herdr desktop app](https://herdr.dev/guide/) manages agents locally and in WSL (as an SSH machine). It runs alongside the herdr TUI above; both stay installed for now. Set up the WSL side first: [linux/README.md](../linux/README.md#herdr-app-windows--wsl).

* Install the app (it also installs herdr-core and then updates itself)
  * `powershell -c "irm https://releases.herdr.dev/app/install.ps1 | iex"`
* Copy the app config (start the app once first, so it creates the folder; it applies changes while running)
  * `herdr-app/.config/herdr-app/settings.json` -> `%USERPROFILE%\.config\herdr-app\settings.json`
  * `herdr-app/.config/herdr-app/themes/dracula.json` -> `%USERPROFILE%\.config\herdr-app\themes\dracula.json` (`settings.json` picks this theme)
  * `herdr-app/.config/herdr-app/mods/tab-autoname/` -> `%USERPROFILE%\.config\herdr-app\mods\tab-autoname\`
    * Names tabs after the work in them, e.g. `Fix login bug (shop ⎇ ABC-142)` for an agent or `.dotfiles ⎇ feature/ps-sync` for a shell. Tabs you name yourself are left alone; to hand one back, clear its name (`herdr-app do tab.rename --id <tab> --name ""`).
    * It's [herdr-tab-autoname](https://github.com/OliverRC/herdr-tab-autoname) at commit `3030a5b`, with one change in `names.js` so folder names and `~` work for Windows paths and for another machine's home (WSL's). To update, copy the newer `mods/tab-autoname/` over it and put that change back.
  * `herdr-app/.config/herdr-app/layouts/my-main.json` -> `%USERPROFILE%\.config\herdr-app\layouts\my-main.json`, then switch to it (`ctrl-shift-l`, or `herdr-app do layout.switch --name my-main`)
    * A copy of Herdr's `main` layout (version 0.1.14) with an invisible block that runs `tab-autoname`: a mod only runs while a layout shows it, and Herdr's own layouts are read-only. The copy doesn't get Herdr's later changes to `main`; to take them, clone `main` again (`herdr-app do layout.clone --name main --as my-main`, after moving the old file aside) and add the root's `floating` entry back.
  * Everything else in that folder is Herdr's own or this machine's state. `keys.json` is left out until a shortcut is changed: Herdr only adds new default shortcuts to a `keys.json` nobody has edited.
  * A file the app rejects is reported in `<name>.error` beside it (e.g. `settings.error`)
* Create an SSH key just for WSL, with no passphrase (Herdr's background reconnects can't type one; the key only works against the localhost-only sshd in WSL)
  * From PowerShell 7: `ssh-keygen -t ed25519 -N '' -C windows-to-wsl-herdr -f $env:USERPROFILE\.ssh\id_ed25519_wsl`
  * Windows PowerShell 5 drops the empty `-N` argument and ssh-keygen waits for a passphrase, so use PowerShell 7 (or run `ssh-keygen.exe` from WSL)
  * Add `id_ed25519_wsl.pub` to WSL's `~/.ssh/authorized_keys` (see the linux steps)
* Add a host for the distro to `%USERPROFILE%\.ssh\config`, named `<distro>-wsl` in lowercase (herdr names a machine after its host, and its names allow only `a-z 0-9 - _ .`)

  ```
  Host debian-wsl
    HostName 127.0.0.1
    Port 2222
    User <WSL user>
    IdentityFile ~/.ssh/id_ed25519_wsl
    IdentitiesOnly yes
  ```

  * Use `127.0.0.1`, not `localhost`: Windows tries `::1` first and WSL only forwards IPv4, so herdr-core fails with `banner exchange: Connection to UNKNOWN port -1: Connection refused`
* Check `ssh debian-wsl` logs in without a prompt (the first run trusts the host key)
* In the app, add a machine and pick `debian-wsl` from the SSH config list
* After `wsl --shutdown`, the machine shows as unreachable and reconnects on its own once WSL is running again

### tailscale (optional)

To reach herdr-core on this machine and in WSL from your phone or other computers by name, set up Tailscale and Windows' OpenSSH server: see [tailscale/README.md](../tailscale/README.md). The app's own connection to WSL above stays on `127.0.0.1:2222` and doesn't use Tailscale.

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

# linux

These setup instructions are for Debian.

> N.B. See [linux tips](#linux-tips) for some general help with common operations.

## Automated setup

The automated install script is in this dotfiles repo so must be cloned first:

* Update distro
  * `sudo apt update && sudo apt upgrade -y`
* Install packages
  * `sudo apt install git -y`
* Clone the repo
  * `git clone https://github.com/CMeeg/dotfiles.git ~/.dotfiles`
  * `cd ~/.dotfiles`

Then run [`bootstrap.sh`](../bootstrap.sh), which installs PowerShell 7 from Microsoft's apt repo and then runs [`install.ps1`](../install.ps1) to automate the full setup:

```bash
# Preview what will be done (still installs PowerShell, which the preview needs)
./bootstrap.sh -WhatIf

# Run the installer (idempotent — safe to run multiple times)
./bootstrap.sh

# Then open a new terminal to reload your shell
```

> Once PowerShell is installed, run the installer directly with `pwsh ./install.ps1` (`-WhatIf` to preview, `-SkipRetire` to skip the retire steps).
> It is idempotent: completed steps are skipped on re-run.
> On the first run, files the repo manages that already exist and differ from the repo (e.g. Debian's default `~/.bashrc`) are backed up to `~/.local/state/dotfiles/backup/` and replaced.

## Automated update

The [`update.ps1`](../update.ps1) script automates applying updates:

```bash
# Preview what will be done
pwsh ./update.ps1 -WhatIf

# Run the updater (will attempt to update all programs installed by the install script)
pwsh ./update.ps1

# Then open a new terminal to reload your shell
```

> On other machines, run `git pull --autostash` in `~/.dotfiles` first, then `pwsh ./update.ps1`, so the updater's own changes (e.g. new retire steps) apply in the same run.
> GitKraken and Node are only reinstalled when a newer version is available; the other programs re-run their installer or update command every time.
> Both `install.ps1` and `update.ps1` run the retire steps first ([`retire.ps1`](../retire.ps1) runs them on their own): they remove tools this repo no longer installs, and the stow links from before the repo switched to `sync.ps1`.

## Syncing dotfiles

[`dotfiles.json`](../dotfiles.json) lists the files this repo manages and where each one goes. [`sync.ps1`](../sync.ps1) copies them into place as real files, and `install.ps1` and `update.ps1` run it for you. Run it yourself after changing a setting, or to pick up changes from another machine:

```bash
pwsh ./sync.ps1            # pull the repo, apply it, then go through local changes
pwsh ./sync.ps1 -NoPull    # apply the repo's working tree as it is, e.g. to try an uncommitted edit
pwsh ./sync.ps1 -WhatIf    # preview
```

* A file changed only in the repo is updated on this machine. A file changed in both places is merged, and a conflict opens VS Code's merge editor (when run in a terminal), or is reported and left alone.
* For each file that differs on this machine (a local change), sync shows the diff with your home path as `@HOME@` (and the repo's path as `@DOTFILES@`) and asks: `c` copies it back into the repo, `s` (or Enter) skips it for this run, `i` ignores it until the file changes again (sync then prints one `-` line instead of the diff, and `-CopyBack` leaves it alone), `d` opens the diff in VS Code. The VS Code diff is for viewing only (left: the repo, right: this machine): edits made there aren't kept, and `c` copies the whole file.
* After copying back, review with `git diff`, stage what you want (`git add -p`), discard the rest and commit. Sync never commits or pushes.
* Tools such as herdr and GitKraken write entries for this machine into `~/.claude/settings.json`, so it differs from the repo on every machine. Answer `i` to stop seeing it until the file changes, or discard those entries from the repo after copying back.
* The `d` option and the merge editor use VS Code (`code`), which works in any WSL terminal, including SSH sessions and the Herdr app's terminals (see [herdr app (Windows) → WSL](#herdr-app-windows--wsl)).
* `-NoPrompt` reports without asking, and `-CopyBack` copies every local change back without asking.

## Migrating a stow machine

Machines set up before the repo moved to `sync.ps1` have their dotfiles linked into the repo by GNU Stow. To move one over:

* Commit and push any dotfile changes you want to keep, but discard entries tools added for this machine (GitKraken's marketplace and plugin entries and herdr's hook in `claude/.claude/settings.json`). The tools add them back: GitKraken on its own, herdr through the installer's setup actions.
* `cd ~/.dotfiles && git pull --autostash`
* `./bootstrap.sh`

The installer's retire steps replace each stow link with a real copy (and record it, so sync treats it as already applied), delete links to files the repo no longer manages, and remove stow.

## Manual setup

### System packages

* Update distro
  * `sudo apt update && sudo apt upgrade -y`
* Install packages
  * `sudo apt install build-essential curl fonts-jetbrains-mono git libnss3-tools python-is-python3 python3 unzip wget -y`

### Starship

* Install [Starship](https://starship.rs/)
  * `curl -sS https://starship.rs/install.sh | sh`

### superfile

* Install [superfile](https://superfile.dev/getting-started/installation/)
  * `bash -c "$(curl -sLo- https://superfile.dev/install.sh)"`
  * Run `spf` to start

### herdr

* Install [herdr](https://herdr.dev/tui/docs/install/)
  * `curl -fsSL https://herdr.dev/install.sh | sh`
  * Run `herdr` to start
  * Config lives at `~/.config/herdr/config.toml` (copied from `herdr/` by sync, below — only `config.toml` is managed; logs, sockets and sessions in that folder stay local)

### herdr app (Windows) → WSL

The [Herdr desktop app](https://herdr.dev/guide/) on Windows can manage agents in this distro by connecting to it as an SSH machine. It runs alongside the herdr TUI above; both stay installed for now. The Windows side is in [windows/README.md](../windows/README.md#herdr-app).

* [herdr-core](https://herdr.dev/core/) (the app's runtime, at `~/.local/bin/herdr-core`): `install.ps1` installs it and `update.ps1` updates it (running terminals keep running), on every Linux machine, since any of them can be added as a machine in the app
* sshd (WSL only; needs `systemd=true` in `/etc/wsl.conf`): `install.ps1` installs `openssh-server`, and the setup actions in `install.ps1` and `update.ps1` install [`linux/sshd_config.d/herdr-wsl.conf`](./sshd_config.d/herdr-wsl.conf) (port 2222 on `127.0.0.1`, key login only) into `/etc/ssh/sshd_config.d/`, check it with `sshd -t` (putting the previous file back if the check fails, since ssh checks its config at every start), then enable and restart ssh
  * Check: `ss -ltn | grep 127.0.0.1:2222`
  * WSL distros share one network, so only one distro per Windows machine can use port 2222. On a second distro the setup action warns that sshd setup failed and the install carries on.
* Interactive shells that `wsl.exe` didn't start (SSH sessions and the Herdr app's terminals, whose server runs as a systemd user service) miss the environment a Windows Terminal WSL tab gets: the Windows `PATH` (so `code`, `explorer.exe`), `WSL_DISTRO_NAME`, and WSLg's `DISPLAY`, `WAYLAND_DISPLAY` and `PULSE_SERVER`. `bash/.bashrc` copies them from a short-lived `wsl.exe` session, adding about 0.3s to each new shell there (Windows Terminal tabs skip it, as `WSL_DISTRO_NAME` is already set). It leaves out `WSL_INTEROP`, as Windows programs run without it.
* Authorise the Windows key (created in the Windows steps); the setup action warns until there's a key
  * `mkdir -p ~/.ssh && chmod 700 ~/.ssh`
  * `cat /mnt/c/Users/<windows user>/.ssh/id_ed25519_wsl.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys`

### Dotfiles (base)

* Clone the repo
  * `git clone https://github.com/CMeeg/dotfiles.git ~/.dotfiles`
* Install PowerShell 7, which the dotfiles scripts run on (`bootstrap.sh` does this)
  * Add Microsoft's apt repo: download `https://packages.microsoft.com/config/debian/<version>/packages-microsoft-prod.deb` (`<version>` is `VERSION_ID` in `/etc/os-release`, e.g. `13`) and `sudo dpkg -i` it
  * `sudo apt update && sudo apt install -y powershell`
* Apply the dotfiles (all of them, including the opencode and Claude Code config below)
  * `cd ~/.dotfiles`
  * `pwsh ./sync.ps1 -NoPull -InitialApply` - `-InitialApply` backs up files that already exist and differ (e.g. Debian's default `~/.bashrc`) to `~/.local/state/dotfiles/backup/` and replaces them
  * See [Syncing dotfiles](#syncing-dotfiles) for what sync reports
* Reload bash profile
  * Open a new terminal
* Create `projects` directory
  * `mkdir ~/projects`

### GitKraken

* Install GitKraken Client
  * `cd /tmp`
  * `wget https://release.gitkraken.com/linux/gitkraken-amd64.deb`
  * `sudo apt install ./gitkraken-amd64.deb -y`
* Run `gitkraken`
* Follow the [setup steps](../gitkraken/README.md)

### Node

* [Install Node](https://nodejs.org/en/download)
  * `curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell` - install fnm (`--skip-shell` because `bash/.bashrc` already sets up fnm)
  * `reload` - reload bash (using alias)
  * `fnm install --lts` - install the latest LTS
  * `fnm default <version>` - make it the default (e.g. `fnm default v26.13.0`; `fnm list` shows installed versions)
  * `node -v` - verify node is installed
* Enable pnpm
  * `corepack enable pnpm` - enable pnpm
  * `pnpm -v` - verify pnpm available

### Chrome

* Install Chrome
  * `cd /tmp`
  * `wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb`
  * `sudo apt install ./google-chrome-stable_current_amd64.deb -y`

> N.B. Chrome can be launched from wsl if needed by running `google-chrome`

### Caddy

* [Install Caddy](https://caddyserver.com/docs/install#debian-ubuntu-raspbian)
  * `sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl`
  * `curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg`
  * `curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list`
  * `sudo chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list`
  * `sudo apt update && sudo apt install -y caddy`
* Disable the bundled systemd service — it serves a default page on port 80, which blocks projects that run `caddy run` themselves
  * `sudo systemctl disable --now caddy`
* Allow unprivileged processes to bind ports 80 and above, so `caddy run` can listen on 80/443 as your own user
  * `echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/50-unprivileged-ports.conf`
  * `sudo sysctl --system`
* Updates come through `sudo apt upgrade`

> N.B. The sysctl is used instead of `sudo setcap cap_net_bind_service=+ep $(which caddy)` because `setcap` is stored on the binary and lost whenever an upgrade replaces it. The sysctl applies machine-wide, which is fine for a dev machine.

### Aspire CLI

* Install the [Aspire CLI](https://aspire.dev/get-started/install-cli/)
  * `curl -sSL https://aspire.dev/install.sh | bash -s -- --skip-path` - installs to `~/.aspire/bin`
  * `--skip-path` stops the installer appending to `~/.bashrc` (which sync manages) — `bash/.bashrc` already adds `~/.aspire/bin` to `PATH`
  * `reload` - reload bash (using alias)
  * `aspire --version` - verify the CLI is installed
* Use the install script on every machine, not the .NET global tool (`dotnet tool install -g aspire.cli`) — the retire steps in `install.ps1` and `update.ps1` remove the global tool if they find it; run `pwsh ./install.ps1` to reinstall Aspire with the script
* Running Aspire apps also needs the [.NET SDK](https://aspire.dev/get-started/prerequisites/) and a container runtime

### OpenCode

* Install [opencode](https://opencode.ai/docs/windows-wsl)
  * `curl -fsSL https://opencode.ai/install | bash`
  * `reload` - reload bash (using alias)
* The config (`opencode.jsonc`, `cli.json`) is applied by sync with the other dotfiles — see [Dotfiles (base)](#dotfiles-base)
* [Superpowers](https://github.com/obra/superpowers) is installed as an opencode plugin — the repo's `opencode.jsonc` already has the entry (V2 shape; needs OpenCode 2.0.4+):
  * `"plugins": ["superpowers@git+https://github.com/obra/superpowers.git"]`
  * opencode fetches and caches it on start — there's nothing to clone
* Run `opencode`
* Run `/connect` and connect a provider

### Claude Code

* See [claude/README.md](../claude/README.md) for install and update instructions (Linux/WSL and Windows)

## Manual updates

* Update distro
  * `sudo apt update && sudo apt upgrade -y` - update distro
* Update GitKraken
  * The `.deb` adds no apt repo, so `apt upgrade` doesn't update it — download and install the latest `.deb` again
  * `wget -O /tmp/gitkraken-amd64.deb https://release.gitkraken.com/linux/gitkraken-amd64.deb`
  * `sudo apt install -y /tmp/gitkraken-amd64.deb`
  * `update.ps1` does this only when a newer version is available
* Update fnm and Node
  * `curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell` - fnm has no self-update, so re-run the installer
  * `fnm install --lts` then `fnm default <version>` - move to the latest LTS
  * Older Node versions stay installed — remove one with `fnm uninstall <version>`
* Update Starship
  * `curl -sS https://starship.rs/install.sh | sh`
* Update superfile
  * `bash -c "$(curl -sLo- https://superfile.dev/install.sh)"` - re-running the installer fetches the latest release
* Update herdr
  * `herdr update`
* Update herdr-core
  * `~/.local/bin/herdr-core update` (running terminals keep running)
* Update Aspire CLI
  * `curl -sSL https://aspire.dev/install.sh | bash -s -- --skip-path` - re-running the installer fetches the latest release
* Update OpenCode
  * `opencode upgrade`
* Update Superpowers
  * opencode caches the plugin, so an update may not show up after a restart — clear opencode's package cache or reinstall the plugin (see `opencode/.config/opencode/README.md`)
* One-time OpenCode v1 → v2 migration
  * See `opencode/.config/opencode/README.md` in this repo
* Update Claude Code
  * `claude update`
* Sync dotfiles
  * `cd ~/.dotfiles && pwsh ./sync.ps1` - pulls the repo (stashing uncommitted changes and restoring them), applies it and goes through local changes; see [Syncing dotfiles](#syncing-dotfiles)
* Reload bash profile
  * `reload` - using alias

## linux tips

* Update a package from a `.deb` file
  * Download the `.deb` file to local disk e.g. to `~/`
  * Run `sudo apt install ~/path-to-package.deb`
  * Delete the downloaded file when done
* If you need to kill a program
  * `pidof <program>` - find pid(s) of program
  * `kill -<signal> <pid(s)>` - send kill signal to pid(s), `15` is SIGTERM, `9` is SIGKILL

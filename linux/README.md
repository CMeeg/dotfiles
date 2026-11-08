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

Then run the [`install.sh`](../install.sh) script to automate the full setup:

```bash
# Preview what will be done
./install.sh --dry-run

# Run the installer (idempotent — safe to run multiple times)
./install.sh

# Reload your shell (using an alias)
reload
```

> The script must be run from within the cloned `~/.dotfiles` directory.
> It is idempotent: completed steps are skipped on re-run.

## Automated update

The [`update.sh`](../update.sh) script automates applying updates:

```bash
# Preview what will be done
./update.sh --dry-run

# Run the updater (will attempt to update all programs installed by the install script)
./update.sh

# Reload your shell (using an alias)
reload
```

> The script must be run from within the cloned `~/.dotfiles` directory.
> On other machines, run `git pull --autostash` in `~/.dotfiles` first (tools such as GitKraken leave `claude/.claude/settings.json` modified, which a plain `git pull` refuses), then `./update.sh`, so the updater's own changes (e.g. new retire steps) apply in the same run.
> GitKraken and Node are only reinstalled when a newer version is available; the other programs re-run their installer or update command every time.

## Manual setup

### System packages

* Update distro
  * `sudo apt update && sudo apt upgrade -y`
* Install packages
  * `sudo apt install build-essential curl fonts-jetbrains-mono git libnss3-tools python-is-python3 python3 stow unzip wget -y`

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
  * Config lives at `~/.config/herdr/config.toml` (stowed from `herdr/` below — only `config.toml` is tracked; logs, sockets and sessions in that folder stay local)

### Dotfiles (base)

* Clone the repo
  * `git clone https://github.com/CMeeg/dotfiles.git ~/.dotfiles`
* Link dotfiles
  * `cd ~/.dotfiles`
  * `stow --adopt --no-folding -v bash git starship superfile herdr`
  * Accept or reject changes to dotfiles (if any)
    * View the diff of the dotfiles repo
    * Accept/merge/reject changes
    * Commit and push, if needed
* Reload bash profile
  * `source ~/.bashrc`
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
  * `--skip-path` stops the installer appending to `~/.bashrc` (which is stowed) — `bash/.bashrc` already adds `~/.aspire/bin` to `PATH`
  * `reload` - reload bash (using alias)
  * `aspire --version` - verify the CLI is installed
* Use the install script on every machine, not the .NET global tool (`dotnet tool install -g aspire.cli`) — `install.sh` and `update.sh` remove the global tool if they find it; run `./install.sh` to reinstall Aspire with the script
* Running Aspire apps also needs the [.NET SDK](https://aspire.dev/get-started/prerequisites/) and a container runtime

### OpenCode

* Install [opencode](https://opencode.ai/docs/windows-wsl)
  * `curl -fsSL https://opencode.ai/install | bash`
  * `reload` - reload bash (using alias)
* Link dotfiles
  * `cd ~/.dotfiles`
  * `stow --adopt --no-folding -v opencode`
  * Accept or reject changes to dotfiles (if any)
    * View the diff of the dotfiles repo
    * Accept/merge/reject changes
    * Commit and push, if needed
* [Superpowers](https://github.com/obra/superpowers) is installed as an opencode plugin — the stowed `opencode.jsonc` already has the entry (V2 shape; needs OpenCode 2.0.4+):
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
  * `update.sh` does this only when a newer version is available
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
* Restow
  * `cd ~/.dotfiles`
  * `git stash`
  * `git pull`
  * `git stash pop` - before stowing, so packages that only exist locally are present
  * `stow --adopt --no-folding -v bash git opencode starship superfile herdr claude`
  * Accept or reject changes to dotfiles (if any)
    * View the diff of the dotfiles repo
    * Accept/merge/reject changes
    * Commit and push, if needed
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

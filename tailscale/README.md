# tailscale

[Tailscale](https://tailscale.com/) puts this laptop, its WSL distro, your phone and your other machines on one private network (a "tailnet"), so they can reach each other by name from anywhere, without opening ports to the internet. Here it's used to reach [herdr-core](https://herdr.dev/core/) from the [Herdr mobile app](https://herdr.dev/mobile/) and from other computers, and to open dev servers remotely.

It's opt-in: `install.ps1` doesn't set it up.

## How it fits together

Windows and WSL join the tailnet as two separate devices, mirroring how the Windows Herdr app already treats WSL as its own machine:

| Device | Name on the tailnet | SSH login (port 22) | herdr-core |
|---|---|---|---|
| Windows | `meeg-laptop` | Windows OpenSSH server, key login, tailnet addresses only | the Herdr app's core |
| WSL (Debian) | `meeg-laptop-wsl` | [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh): Tailscale checks who you are, so no keys | `~/.local/bin/herdr-core` |

* The Herdr mobile app talks to herdr-core over SSH, and lists your Tailscale devices to pick from.
* The Windows Herdr app keeps reaching WSL as it does now, over `127.0.0.1:2222` (see [linux/README.md](../linux/README.md#herdr-app-windows--wsl)). That's localhost traffic: Tailscale doesn't touch it, and it keeps working with Tailscale stopped. Tailscale is only for connecting from other devices. The Windows app can also use it to add other machines on your tailnet, e.g. `hc machine add <user>@<their name>`.
* SSH uses port 22, so there's no port number to remember: the device name is enough.

> N.B. Tailscale's own docs recommend running Tailscale on [the Windows host only, not inside WSL 2](https://tailscale.com/docs/install/windows/wsl2), because of packet-size (MTU) limits; `tailscaled` raises WSL's MTU to work around it. Running it in both is what gives WSL its own name and Tailscale SSH. If connections to `meeg-laptop-wsl` hang while `tailscale ping meeg-laptop-wsl` works, that's the likely cause.

## Friendly names

* [MagicDNS](https://tailscale.com/kb/1081/magicdns) (on by default) lets any tailnet device use the short name, e.g. `ssh meeg@meeg-laptop-wsl` or `http://meeg-laptop-wsl:5173`. The full name is `meeg-laptop-wsl.<tailnet>.ts.net`, which HTTPS needs (see [Dev servers](#dev-servers-and-other-services)). Your tailnet's name is under DNS in the admin console, where you can swap the random one for a friendlier [fun name](https://tailscale.com/kb/1217/tailnet-name).
* A device's name comes from its hostname, which for this laptop is `LAPTOP-LEO2VFVM`. Set a better one with `tailscale set --hostname=<name>` on the device (`tailscale.ps1 -Hostname` does this in WSL), or with Edit machine name in the admin console. Without it, WSL would join as `laptop-leo2vfvm`, since WSL takes its hostname from Windows.
* Names are unique across the tailnet: a device that asks for a name another device already has gets a number added (e.g. `meeg-laptop-wsl-1`), and keeps it after the other device goes. `tailscale.ps1` warns when that happens.

## Tailnet settings (once, in the [admin console](https://login.tailscale.com/admin))

* **DNS**: check MagicDNS is on, and turn on HTTPS Certificates (needed for `tailscale serve` over HTTPS)
* **Access controls**: the default SSH rule uses `check` mode, which asks you to log in again in a browser every 12 hours, and the Herdr app can't do that for you. For your own devices, switch it to `accept` and leave out `root`:

  ```json
  "ssh": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["autogroup:self"],
      "users": ["autogroup:nonroot"]
    }
  ]
  ```

* **Machines**: once `meeg-laptop` and `meeg-laptop-wsl` have joined, choose Disable key expiry on each (⋯ menu). Otherwise they drop off the tailnet every 180 days until you log in on them again.

## WSL (`meeg-laptop-wsl`)

### Automated

```bash
pwsh ./tailscale.ps1 -Hostname meeg-laptop-wsl -WhatIf   # preview
pwsh ./tailscale.ps1 -Hostname meeg-laptop-wsl           # log in by opening the link it prints
```

[`tailscale.ps1`](../tailscale.ps1) does the manual steps below and is idempotent. Re-run it without `-Hostname` to put the settings back if they've changed, or to reconnect after `tailscale down` or an expired login; with `-Hostname`, it renames the device. The first run needs `-Hostname`: without it, the script stops with an error.

To log in without a browser (e.g. on a headless machine), create an auth key in the admin console (Settings → Keys; one-off, short expiry), add `export TS_AUTHKEY=tskey-auth-...` to `~/.secrets`, open a new terminal and run the script. The script hands the key to `tailscale` as a temporary file, not on the command line. Remove the line from `~/.secrets` afterwards: the key is only needed to join.

### Manual

* Install Tailscale (adds Tailscale's apt repo, so `sudo apt upgrade`, and so `update.ps1`, keeps it up to date)
  * `curl -fsSL https://tailscale.com/install.sh | sh`
* Make sure `tailscaled` runs at boot (needs `systemd=true` in `/etc/wsl.conf`)
  * `sudo systemctl enable --now tailscaled`
* Join the tailnet (open the link it prints)
  * `sudo tailscale up --ssh --operator=$USER --hostname=meeg-laptop-wsl --accept-dns=false`
  * `--ssh` turns on Tailscale SSH, so tailnet devices log in without keys. It only answers on the tailnet address, so the Windows Herdr app's sshd on `127.0.0.1:2222` is unaffected
  * `--operator=$USER` lets you run `tailscale serve` and other `tailscale` commands without `sudo`
  * `--accept-dns=false` leaves DNS to Windows: WSL tunnels DNS through the Windows host (its `/etc/resolv.conf` points at `10.255.255.254`), and the host's Tailscale already resolves tailnet names. Otherwise `tailscaled` would rewrite the `resolv.conf` WSL generates. Leave it out on a Linux machine that isn't WSL
* Change settings later with `sudo tailscale set ...`, e.g. `sudo tailscale set --hostname=<name>`

### Check

* `tailscale status` lists this device as `meeg-laptop-wsl`, and your other devices
* From another tailnet device: `ssh meeg@meeg-laptop-wsl` logs in without a password or key

### Keep WSL running

The phone can only reach `meeg-laptop-wsl` while WSL is running (and the laptop is awake): it can't start WSL. If it shows as offline while a WSL terminal is closed, a logon task on Windows can keep the distro running. In PowerShell:

```powershell
$action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument '--headless wsl.exe -d Debian --exec sleep infinity'
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'Keep WSL running' -Action $action -Trigger $trigger -Settings $settings
```

Remove it with `Unregister-ScheduledTask -TaskName 'Keep WSL running'`.

## Windows (`meeg-laptop`)

Windows is set up by hand. Tailscale SSH has no Windows server, so the phone logs in through Windows' own OpenSSH server, limited to tailnet addresses and to keys.

### Tailscale

* Install Tailscale
  * `winget install --id Tailscale.Tailscale`
* Log in from the Tailscale icon in the system tray
* Rename the device (or use Edit machine name in the admin console)
  * `tailscale set --hostname=meeg-laptop`
* Optional: tray icon → Settings → Run unattended, so the laptop stays on the tailnet while you're signed out of Windows (locking the screen doesn't need it)

### OpenSSH server

From PowerShell 7 run as administrator:

* Install the server (Settings → System → Optional features also has it; already installed on this laptop)
  * `Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`
* Start it now and at every boot
  * `Set-Service sshd -StartupType Automatic; Start-Service sshd`
* Accept SSH only from tailnet addresses (installing the server adds a firewall rule that allows any address)
  * `Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -RemoteAddress 100.64.0.0/10, fd7a:115c:a1e0::/48`
  * If that rule is missing: `New-NetFirewallRule -Name OpenSSH-Server-In-TCP -DisplayName 'OpenSSH Server (sshd)' -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -RemoteAddress 100.64.0.0/10, fd7a:115c:a1e0::/48`
* Turn off password logins: in `C:\ProgramData\ssh\sshd_config` (open it as administrator), change the `#PasswordAuthentication yes` line near the top to `PasswordAuthentication no`, then `Restart-Service sshd`. Don't add it at the end instead: the file ends with a `Match Group administrators` block, and lines after it only apply to that block

### Keys

Your Windows account is an administrator, so the server reads its keys from `C:\ProgramData\ssh\administrators_authorized_keys`, not `~\.ssh\authorized_keys`. The file must belong to Administrators and SYSTEM only, or the server ignores it.

* Get the phone's public key from the Herdr app (WSL doesn't need it, because it uses Tailscale SSH), or a computer's `~/.ssh/id_ed25519.pub`
* From PowerShell 7 run as administrator:
  * `Add-Content -Path C:\ProgramData\ssh\administrators_authorized_keys -Value '<public key>'`
  * `icacls.exe C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F'`

### herdr-core

* The Herdr app installs and updates herdr-core. Keep the app open (or run `hc server start` in a normal terminal) when connecting from elsewhere: herdr-core warns that an SSH login as an administrator starting the core could block your desktop session.

### Check

* From another tailnet device: `ssh cpmee@meeg-laptop` logs in without a password

## Connecting from the phone

* Install the Tailscale app ([Android](https://play.google.com/store/apps/details?id=com.tailscale.ipn), [iOS](https://apps.apple.com/app/tailscale/id1470499037)) and log in with the same account
* Install the [Herdr app](https://herdr.dev/mobile/) and add a machine from your Tailscale devices:
  * `meeg-laptop-wsl` as user `meeg` (Tailscale SSH: no key)
  * `meeg-laptop` as user `cpmee` (needs the phone's key in [Keys](#keys))
* Once one machine is connected, the app also offers the machines that computer's Herdr already uses. Skip `debian-wsl`: it's the Windows app's `127.0.0.1:2222` link, which only works on the laptop itself. Use `meeg-laptop-wsl` instead
* Agents and terminals show from both. Spaces only show for `meeg-laptop`, where the Herdr app runs; agents started in the old herdr TUI don't show

## Connecting from another computer

* Install Tailscale there and log in
* Plain SSH: `ssh meeg@meeg-laptop-wsl` or `ssh cpmee@meeg-laptop`
* herdr-core: `hc machine add meeg@meeg-laptop-wsl` (it's named `meeg-laptop-wsl`), then `hc run --on meeg-laptop-wsl ...`, or add it in that computer's Herdr app
* An entry in `~/.ssh/config` saves typing the user each time:

  ```
  Host meeg-laptop-wsl
    User meeg
  ```

## Dev servers and other services

To open a dev server running on the laptop from the phone or another computer:

### `tailscale serve` (recommended)

Publishes a local port to your tailnet over HTTPS, with a real certificate, at the device's full name. The dev server can stay on `localhost`, and only tailnet devices can reach it. In the same environment as the server (WSL or Windows):

```bash
tailscale serve --bg 5173                  # https://meeg-laptop-wsl.<tailnet>.ts.net → http://localhost:5173
tailscale serve --bg --https=8443 3000     # a second one on https://...:8443
tailscale serve --bg --set-path=/api 5000  # or under a path of the first
tailscale serve status                     # what's published
tailscale serve reset                      # stop publishing all of it
```

* Without `--bg`, it serves until you press Ctrl+C
* The first request takes a few seconds while Tailscale gets the certificate
* Dev servers that check the `Host` header reject the new name until allowed, e.g. Vite's `server.allowedHosts: ['.ts.net']`. Apps that build absolute URLs or OAuth callbacks from `localhost` need the same treatment
* WSL runs it without `sudo` because `tailscale.ps1` made you the operator. On Windows, run it in your own terminal

### Straight to the port

Quicker for a one-off: start the server listening on all addresses (e.g. `vite --host`, `--urls http://0.0.0.0:5000`), then open `http://meeg-laptop-wsl:5173`. It's plain HTTP, and you need the port. A server running on Windows also needs a firewall rule for its port; in WSL, nothing else is needed.

### Not used here

* [Funnel](https://tailscale.com/kb/1223/funnel) publishes to the public internet: only for sharing with people outside your tailnet
* [Tailscale Services](https://tailscale.com/kb/1552/tailscale-services) give each service its own name (e.g. `myapp.<tailnet>.ts.net`), but the device hosting them must be tagged, which takes it out of your personal devices (and the SSH rule above)

## Removing

* WSL:
  * `sudo tailscale logout && sudo apt remove -y tailscale`
  * Remove Tailscale's apt repo, so `apt update` stops checking it: `sudo rm /etc/apt/sources.list.d/tailscale.list /usr/share/keyrings/tailscale-archive-keyring.gpg`
* Windows, from PowerShell 7 run as administrator:
  * Uninstall Tailscale: `winget uninstall --id Tailscale.Tailscale`
  * Stop the SSH server: `Stop-Service sshd; Set-Service sshd -StartupType Manual`
  * Put the firewall rule back to allowing any address: `Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -RemoteAddress Any`
  * Remove the keys you added from `C:\ProgramData\ssh\administrators_authorized_keys`
  * If you added the [Keep WSL running](#keep-wsl-running) task: `Unregister-ScheduledTask -TaskName 'Keep WSL running' -Confirm:$false`
* Then remove the devices in the admin console

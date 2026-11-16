# tailscale

[Tailscale](https://tailscale.com/) puts this machine, your phone and your other computers on one private network (a "tailnet"), so they can reach each other from anywhere, without opening ports to the internet. Here it's used to reach [herdr-core](https://herdr.dev/core/) on Windows and in WSL from the [Herdr mobile app](https://herdr.dev/mobile/) and from other computers, and to open dev servers by name through the [dev proxy](../dev-proxy/README.md).

It's optional and for personal machines: `install.ps1` doesn't set it up. Each step is labelled as in the dev proxy guide: *tested* (run on Windows 11 with an Android phone), *observed* or *docs only*.

## How it fits together

Tailscale runs on Windows only, and Windows is the one device on the tailnet, named `<host>`:

| What | Reached from the tailnet at | Through |
|---|---|---|
| The Windows host | `<host>`, port 22 | Windows' OpenSSH server, key login, Tailscale's address range only |
| WSL | `<host>`, port 2222 | Tailscale forwarding to WSL's SSH server on `127.0.0.1:2222` |
| Dev servers | `https://<app>.<machine>.<personal domain>` | Tailscale forwarding port 443 to the dev proxy |

- **Why not in WSL too:** all WSL 2 distros share one network, so only one could be its own tailnet device, and Tailscale advises running it [on the Windows host only](https://tailscale.com/docs/install/windows/wsl2). The Herdr mobile app takes an address, user and port, so a forwarded port reaches WSL just as well.
- **The Windows Herdr app** keeps reaching WSL as it does now, over `127.0.0.1:2222` (see [linux/README.md](../linux/README.md#herdr-app-windows--wsl)). That's localhost traffic: Tailscale doesn't touch it, and it keeps working with Tailscale stopped.
- **`<machine>`** is the label in the dev servers' names, e.g. `laptop` in `myapp.laptop.example.net`. It marks a name as tailnet-only, and can be the same word as `<host>`.

## Friendly names

- [MagicDNS](https://tailscale.com/docs/features/magicdns) (on by default) lets any tailnet device use the short name, e.g. `ssh <user>@<host>`. The full name is `<host>.<tailnet>.ts.net`.
- A device's name comes from its hostname, which Windows often sets to something like `LAPTOP-ABC1234`. Set a better one with `tailscale set --hostname=<host>`, or with Edit machine name in the admin console.
- Names are unique across the tailnet: a device that asks for a name another device already has gets a number added (e.g. `<host>-1`), and keeps it after the other device goes.

## Tailnet settings (once, in the [admin console](https://login.tailscale.com/admin))

- **Machines:** once `<host>` has joined, choose Disable key expiry on it (⋯ menu). Otherwise it drops off the tailnet every 180 days until you log in on it again ([key expiry](https://tailscale.com/docs/features/access-control/key-expiry)).
- **Nothing else:** this set-up doesn't use Tailscale SSH or `tailscale serve`'s HTTPS, so it needs no SSH rule and no HTTPS Certificates.

## Windows (`<host>`)

Windows is set up by hand, from PowerShell 7.

### Tailscale

- **Install** ([Install on Windows](https://tailscale.com/docs/install/windows)): `winget install --id Tailscale.Tailscale` *(tested; not in Tailscale's docs, which link the installer)*. It installs for all users, so it asks for elevation.
- **Log in** from the Tailscale icon in the system tray.
- **Rename the device** (or use Edit machine name in the admin console): `tailscale set --hostname=<host>`.
- **Optional:** tray icon → Settings → Run unattended, so the machine stays on the tailnet while you're signed out of Windows; locking the screen doesn't need it ([run unattended](https://tailscale.com/docs/how-to/run-unattended)).

### OpenSSH server

Windows' own SSH server is how tailnet devices log in to the Windows host, limited to tailnet addresses and to keys *(tested)*. From PowerShell 7 run as administrator ([get started with OpenSSH](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse), [server configuration](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration)):

- **Install the server** (Settings → System → Optional features also has it): `Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`.
- **Start it now and at every boot:** `Set-Service sshd -StartupType Automatic; Start-Service sshd`.
- **Accept SSH only from Tailscale's address range** ([tailnet addresses](https://tailscale.com/docs/concepts/tailscale-ip-addresses)); installing the server adds a firewall rule that allows any address:
  - `Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -RemoteAddress 100.64.0.0/10, fd7a:115c:a1e0::/48`
  - if that rule is missing: `New-NetFirewallRule -Name OpenSSH-Server-In-TCP -DisplayName 'OpenSSH Server (sshd)' -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -RemoteAddress 100.64.0.0/10, fd7a:115c:a1e0::/48`
  - **Not quite tailnet-only:** `100.64.0.0/10` is the shared address range that some ISPs, mobile and hotel networks also use, so a device on such a local network could reach the port too. Key login still keeps it out. Adding `-InterfaceAlias Tailscale` to the rule would limit it to Tailscale's network adapter *(docs only, not tested)* ([Set-NetFirewallRule](https://learn.microsoft.com/en-us/powershell/module/netsecurity/set-netfirewallrule)).
- **Turn off password logins:** in `C:\ProgramData\ssh\sshd_config` (open it as administrator), change the `#PasswordAuthentication yes` line near the top to `PasswordAuthentication no`, then `Restart-Service sshd`. Don't add it at the end instead: the file ends with a `Match Group administrators` block, and lines after it only apply to that block. `sshd_config` only exists once the server has started once. Afterwards the server still lists `keyboard-interactive` as a method, but answers it with a failure and no password prompt *(tested)*.

### Keys

An administrator's keys are read from `C:\ProgramData\ssh\administrators_authorized_keys`, not `~\.ssh\authorized_keys`, and the file must belong to Administrators and SYSTEM only, or the server ignores it ([key management](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement)).

- **The keys:** the phone's public key from the Herdr app, or a computer's `~/.ssh/id_ed25519.pub`. The phone's key goes in WSL's `~/.ssh/authorized_keys` too, for [SSH to WSL](#ssh-to-wsl).
- **Adding one,** from PowerShell 7 run as administrator:
  - `Add-Content -Path C:\ProgramData\ssh\administrators_authorized_keys -Value '<public key>'`
  - `icacls.exe C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F'`

### herdr-core

- The Herdr app installs and updates herdr-core. Keep the app open (or run `hc server start` in an ordinary terminal) when connecting from elsewhere: herdr-core warns that an SSH login as an administrator starting the core could block your desktop session.

### Check

- From another tailnet device: `ssh <user>@<host>` logs in without a password.

## SSH to WSL

Tailscale forwards the tailnet's port 2222 to WSL's existing SSH server, which the Windows Herdr app already uses on `127.0.0.1:2222` *(tested)*.

- **The forward,** in an ordinary terminal, no admin rights needed ([tailscale serve](https://tailscale.com/docs/reference/tailscale-cli/serve)):

  ```powershell
  tailscale serve --bg --tcp=2222 tcp://127.0.0.1:2222
  ```

  It's a raw TCP forward that reaches WSL through WSL's localhost forwarding, and it comes back by itself after Tailscale reconnects. A full Windows restart wasn't tried. `tailscale serve status` shows it.
- **Security:** the forward makes WSL's SSH server reachable from every device on your tailnet, and the server sees each connection as coming from `127.0.0.1`. Key login only, as [linux/README.md](../linux/README.md#herdr-app-windows--wsl) sets the server up, is what keeps it safe.

### Keep WSL running

The phone can only reach WSL while it's running (and the machine is awake): it can't start WSL. If it can't connect while no WSL terminal is open, a logon task can keep the distro running ([Register-ScheduledTask](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask)). In PowerShell:

```powershell
$action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument '--headless wsl.exe -d Debian --exec sleep infinity'
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'Keep WSL running' -Action $action -Trigger $trigger -Settings $settings
```

`conhost.exe --headless` runs `wsl.exe` with no window. *Not in official docs:* no Microsoft page documents `--headless`.

## Connecting from the phone

- **Tailscale:** install the Tailscale app ([Android](https://play.google.com/store/apps/details?id=com.tailscale.ipn), [iOS](https://apps.apple.com/app/tailscale/id1470499037)) and log in with the same account.
- **The Windows host,** in the [Herdr app](https://herdr.dev/mobile/): add `<host>` as `<user>`, port 22. The phone's key must be in [Keys](#keys).
- **WSL,** in the Herdr app, in this order *(tested)*:
  1. add a machine with `<host>` (or its `100.x` address, if the phone has "Use Tailscale DNS" off: see [Optional: DNS filters](#optional-dns-filters)), user `<WSL user>` and port `2222`; the app then shows its public key;
  2. add that key to `~/.ssh/authorized_keys` in WSL, e.g. with the comment `herdr-mobile`, beside the Windows app's key;
  3. choose **Connect again**.

  The app uses one key for every machine, so once that key is in WSL's `authorized_keys` (or was added for the Windows host first), it connects straight away without showing it *(tested)*.
- **Names in the app:** it names each machine after the address you enter, so rename them, e.g. `<host>` and `<host>-wsl`.
- **Skip `debian-wsl`:** once one machine is connected, the app also offers the machines that computer's Herdr already uses. `debian-wsl` is the Windows app's `127.0.0.1:2222` link, which only works on the Windows machine itself.
- **What shows:** agents and terminals show from both. Spaces only show for the Windows host, where the Herdr app runs; agents started in the old herdr TUI don't show.

## Connecting from another computer

- Install Tailscale there and log in.
- **Plain SSH:** `ssh <user>@<host>` for Windows, `ssh -p 2222 <WSL user>@<host>` for WSL.
- **herdr-core:** `hc machine add <WSL user>@<host>:2222 --name <host>-wsl`, then `hc run --on <host>-wsl ...`, or add it in that computer's Herdr app. Without `--name`, it's named after the host, the same as the Windows machine *(docs only: from `hc machine add --help`)*.
- **An entry in `~/.ssh/config`** saves typing the port and user each time:

  ```
  Host <host>-wsl
    HostName <host>
    Port 2222
    User <WSL user>
  ```

## Dev servers by name on the tailnet

Each dev server gets a name like `https://myapp.<machine>.<personal domain>` that only your tailnet devices can reach, with a real certificate. The [dev proxy](../dev-proxy/README.md#windows-also-windows--wsl) serves it, with a Let's Encrypt wildcard certificate it gets through Cloudflare's API *(tested)*. This needs the dev proxy set up first, and the domain on Cloudflare.

1. **The DNS record** ([create DNS records](https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/)): in the domain's DNS → Records → **Add record**: type `A`, name `*.<machine>`, IPv4 address the Windows host's tailnet address (`tailscale ip -4`), proxy status off (*DNS only*). Cloudflare shows it as "DNS only - reserved IP", as it can't proxy a tailnet address.
2. **The API token** ([create API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)): My Profile → API Tokens → **Create Token**, from scratch, with a *Zone* policy for the one domain granting Zone → Read and DNS → Edit, and a **Token expiration** date. The secret is shown once, so save it straight away, in the next step.
3. **The token file:** open Notepad as administrator, paste the token, and save it as `C:\Windows\System32\config\systemprofile\AppData\Roaming\Caddy\cloudflare.token` (*Save as type*: *All files*). Only administrators and the service can read that folder. Never paste the token into a terminal or a chat.
   - **How safe that is:** Caddy reads the file itself, so the token is only as safe as Caddy's config. In the dev proxy's default set-up, any local process can change that config through the admin API, or by adding a file to `C:\ProgramData\Caddy\sites`, e.g. with a site that sends the file's contents back, and the token can edit the domain's DNS. On a machine that holds the token, use the [hardened set-up](../dev-proxy/README.md#optional-the-hardened-set-up), which turns the admin API off and keeps the config where only administrators can write.
4. **Caddy's Cloudflare plugin,** as administrator, with the service stopped ([caddy add-package](https://caddyserver.com/docs/command-line#caddy-add-package)):

   ```powershell
   sc.exe stop caddy
   & 'C:\Program Files\Caddy\caddy.exe' add-package github.com/caddy-dns/cloudflare
   sc.exe start caddy
   ```

   - **What it does:** it downloads a build of the latest release with the plugin added from caddyserver.com, and replaces `caddy.exe`. Here it left the old binary beside it as `caddy.exe.tmp` *(observed, twice)*; delete that once the new one works (`list-modules` below).
   - **Check:** `& 'C:\Program Files\Caddy\caddy.exe' list-modules` lists `dns.providers.cloudflare`.
   - **Updates:** use `caddy upgrade`, which keeps the plugins ([caddy upgrade](https://caddyserver.com/docs/command-line#caddy-upgrade)), *docs only*, rather than the dev proxy's zip, which has no plugins. Both commands are marked experimental in Caddy's docs.
5. **The site:** copy [tailnet.caddy](./tailnet.caddy) into the `sites` folder (`C:\ProgramData\Caddy\sites\`, or `C:\Program Files\Caddy\sites\` with the hardened set-up) as administrator, change `laptop.example.net` to `<machine>.<personal domain>`, and add a `handle` for each app. Then restart the service: `sc.exe stop caddy; sc.exe start caddy`. *Tested* with the hardened set-up, where a restart is the only way to apply it.
   - **The certificate:** the log (the dev proxy's logging block) shows `certificate obtained successfully` for `*.<machine>.<personal domain>` from Let's Encrypt within a minute of the restart. Windows' `curl.exe` accepts it without `--ssl-no-revoke`, unlike Caddy's local certificates.
   - **The dev server's host check:** add each tailnet name to it, as for a tunnel name ([the dev proxy's step 8](../dev-proxy/README.md#windows-also-windows--wsl)). Until then, Vite answers `403`.
   - **The token** is read with Caddy's `{file.…}` placeholder, which keeps it out of the service's environment, which Windows keeps in the registry ([placeholders](https://caddyserver.com/docs/caddyfile/concepts#placeholders)). It doesn't keep it from Caddy's config (step 3).
   - **No `bind`:** a site bound to the tailnet address stops the whole service starting while Tailscale is down, `.localhost` sites included. The site stays on loopback, and Tailscale forwards to it (next step).
   - **Other names** under `*.<machine>` get `404`.
6. **The forward,** in an ordinary terminal ([tailscale serve](https://tailscale.com/docs/reference/tailscale-cli/serve)):

   ```powershell
   tailscale serve --bg --tcp=443 tcp://127.0.0.1:443
   ```

   - **Raw TCP:** Tailscale passes the TLS connection through, so the phone sees Caddy's Let's Encrypt certificate.
   - **Tested:** with Tailscale disconnected, Caddy kept serving its local sites and restarted cleanly; after reconnecting, the forward came back by itself. A full Windows restart wasn't tried.
7. **Check from the phone:** open `https://myapp.<machine>.<personal domain>` with Tailscale connected. With Tailscale disconnected, the name still resolves but the page fails with `ERR_ADDRESS_UNREACHABLE` (Chrome on Android) *(tested)*.

**Security:** the 443 forward lets any tailnet device reach every site Caddy serves on loopback, if it asks for that name: `.localhost` sites and the port wildcard too, not just the tailnet names.

## Optional: DNS filters

Some steps exist only because of a DNS filter, such as NextDNS (see also [the dev proxy's DNS filters section](../dev-proxy/README.md#optional-dns-filters)). Without a filter, none of them is needed *(tested with NextDNS)*.

- **The filter has rebinding protection:** it hides records that point at private addresses, so the tailnet names don't resolve. Exempt the domain in the filter, on every network and device that uses it, e.g. NextDNS's Allowlist ([Tailscale: DNS rebinding](https://tailscale.com/docs/reference/faq/dns-rebinding), [NextDNS](https://help.nextdns.io/t/q6hl0vb/support-whitelist-for-dns-rebinding-protection)).
- **A filter app blocks direct DNS on port 53** (e.g. the NextDNS Windows app): Caddy can't check that the challenge record has spread, and the log shows "dial tcp 1.0.0.1:53: … forbidden by its access permissions". Uncomment `propagation_delay 30s` and `propagation_timeout -1` in `tailnet.caddy` to leave that check to Let's Encrypt ([tls](https://caddyserver.com/docs/caddyfile/directives/tls)). Check the log before adding them: on a later set-up with the NextDNS app running, direct DNS worked and the certificate came without them *(observed)*.
- **An Android phone has a Private DNS hostname** (Settings → Private DNS): it loses all DNS once Tailscale connects ([tailscale#4252](https://github.com/tailscale/tailscale/issues/4252)). Turn off "Use Tailscale DNS" in the phone's Tailscale app (Settings → DNS settings). The phone then uses addresses rather than Tailscale names, while names on your domain still resolve through the filter. Other fixes, not tried: set Private DNS to Automatic, or make NextDNS the tailnet's DNS ([Tailscale: NextDNS](https://tailscale.com/docs/integrations/nextdns)), which changes DNS for every tailnet device.

## Removing

- **The forwards,** in an ordinary terminal: `tailscale serve reset`.
- **The tailnet site:** delete `tailnet.caddy` from `C:\ProgramData\Caddy\sites\` as administrator, then `sc.exe stop caddy; sc.exe start caddy`. The plugin build stays until Caddy itself is removed ([the dev proxy's Removing](../dev-proxy/README.md#removing)).
- **In Cloudflare:** delete the `*.<machine>` DNS record, and the API token (My Profile → API Tokens).
- **The token file:** delete `C:\Windows\System32\config\systemprofile\AppData\Roaming\Caddy\cloudflare.token` as administrator.
- **The certificate:** the Let's Encrypt name stays in public certificate logs; that can't be undone.
- **Tailscale:** `winget uninstall --id Tailscale.Tailscale`, then remove `<host>` in the admin console.
- **The phone:** delete its key from WSL's `~/.ssh/authorized_keys` and from `C:\ProgramData\ssh\administrators_authorized_keys`, and remove the machines in the Herdr app.
- **The optional DNS-filter changes:** remove the domain from the filter's allowlist, and turn "Use Tailscale DNS" back on in the phone's Tailscale app.
- **Windows,** from PowerShell 7 run as administrator:
  - stop the SSH server: `Stop-Service sshd; Set-Service sshd -StartupType Manual`;
  - the firewall rule: if installing the server created it, put it back to allowing any address with `Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -RemoteAddress Any`; if you created it with `New-NetFirewallRule`, delete it with `Remove-NetFirewallRule -Name OpenSSH-Server-In-TCP`;
  - password logins: change `PasswordAuthentication no` in `C:\ProgramData\ssh\sshd_config` back to `#PasswordAuthentication yes`;
  - remove the other keys you added from `C:\ProgramData\ssh\administrators_authorized_keys`;
  - optionally, remove the server itself: `Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`;
  - if you added the [Keep WSL running](#keep-wsl-running) task: `Unregister-ScheduledTask -TaskName 'Keep WSL running' -Confirm:$false`.

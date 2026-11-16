# Dev proxy

The dev proxy is one always-on [Caddy](https://caddyserver.com/docs/) that every dev server sits behind, so each project's dev server has a name rather than a port number, on the machine itself and from other devices. Names reached from other devices are on a domain you control, and one-off dev servers can get a name with no set-up at all.

One project's names, side by side:

| Name | Reached from | Example |
|---|---|---|
| `<app>.localhost` | this machine only, even offline | `myapp.localhost` |
| `<person>-<app>.<work domain>` | anywhere, through that person's tunnel, behind a login | `person-myapp.example.com` |
| `<app>.<personal domain>` | anywhere, through the machine's tunnel, behind a login | `myapp.example.net` |
| `<app>.<machine>.<personal domain>` | your own devices, through Tailscale | `myapp.laptop.example.net` |

The local name needs only the Windows steps below, or the [macOS](#macos) ones, which are untested. The tunnel names are covered in [Tunnels](#tunnels), and the Tailscale name, an optional extra for personal machines, in [tailscale/README.md](../tailscale/README.md). To set up a whole machine, start at [Setting up a machine](#setting-up-a-machine).

Each step is labelled:

- *tested*: run on Windows 11 with Caddy 2.11.9, Vite 8.3.8, Next 16.4.6 and Chrome;
- *observed*: seen while testing, but not something the steps set up;
- *docs only*: follows the linked official docs, but hasn't been run here.

The files this guide copies are beside it: [Caddyfile](./Caddyfile) (the top file), [sites/ports.caddy](./sites/ports.caddy) (a name for any port) and [example.caddy](./example.caddy) (the template for a project's sites file).

## Setting up a machine

The order to set a machine up in, what to check and decide first, and the one check that shows each part worked. Each part's steps are in its own section. This order was followed on a personal Windows 11 machine with WSL *(tested)*; the work and Mac rows below are *docs only*.

Commands that need administrator rights, and changes in Cloudflare's, Tailscale's or a DNS filter's dashboard, are made by the person whose machine or account it is, unless they hand some to an agent helping them, one approved change at a time. An agent prepares them and checks the result, and never handles a token.

### Before you start

Check what's already on the machine, without changing anything:

- [ ] **Caddy on Windows:** a `caddy` service (`sc.exe query caddy`); `C:\Program Files\Caddy` and `C:\ProgramData\Caddy`; a per-user Caddy from winget or Chocolatey (`winget list --id CaddyServer.Caddy`, `choco list caddy`) and its `%APPDATA%\Caddy`; *Caddy Local Authority* roots in your store (`certutil -user -store Root`).
- [ ] **Ports:** what listens on 80, 443, 2019 and 5399 (`Get-NetTCPConnection -State Listen`), and whether IIS is installed (`Get-Service W3SVC`).
- [ ] **WSL:** an apt-installed Caddy (`dpkg -l caddy`), the low-ports sysctl (`/etc/sysctl.d/50-unprivileged-ports.conf`), old roots in `/usr/local/share/ca-certificates/`, and whether WSL's clone of this repo is up to date (`git -C ~/.dotfiles status -sb` after a `git fetch`).
- [ ] **Projects that ran their own Caddy:** Caddyfiles and scripts that run `caddy run` in your project folders. They keep working until moved, but compete for ports 80 and 443 with the service ([Moving a project onto the service](#moving-a-project-onto-the-service)).
- [ ] **`cloudflared`:** every copy on `PATH` (`Get-Command cloudflared -All`), and what's in `%USERPROFILE%\.cloudflared`: a `config.yml` there can stop quick tunnels working.
- [ ] **Personal machines:** whether Tailscale is installed (`tailscale status`, `tailscale serve status`), the SSH server (`Get-Service sshd`) and its firewall rule's addresses, and whether a DNS filter such as NextDNS runs on the machine or the phone ([DNS filters](../tailscale/README.md#optional-dns-filters)).
- [ ] **Old cloud set-up,** if the machine was set up before: tunnels, Access applications, DNS records and API tokens for it in Cloudflare, and the device in Tailscale's admin console.

Then decide:

- **Which parts apply,** from the table below.
- **Default or [hardened](#optional-the-hardened-set-up) set-up:** hardened on a machine that will hold the Cloudflare API token for Tailscale names; the default is simpler anywhere else.
- **Start type:** `start= auto` without IIS, so the names come back after a restart; `start= demand` with IIS ([If you also use IIS](#if-you-also-use-iis)).
- **Duplicates:** uninstall other copies of Caddy (winget's, Chocolatey's) and of `cloudflared`, so the one the guide installs is the one that runs.
- **What to reset:** anything old from the checklist that won't be reused.

Keep a list of each change you make with how to undo it; [Removing](#removing) covers the whole set-up.

| Machine | Parts |
|---|---|
| Personal Windows machine | Everything: the dev proxy, a tunnel for the machine on the [personal domain](#personal-domain), and [Tailscale](../tailscale/README.md) for SSH, WSL and the tailnet names |
| Work Windows machine | The dev proxy and the person's own tunnel on the work domain, run with the token the work account's admin hands over ([Regular access](#regular-access-a-named-tunnel)); nothing in the work account is changed except by its admins. No Tailscale |
| A second personal machine on the same domain | As the first, with its own tunnel using a route per app, as the first machine's `*` route already covers the domain ([Personal domain](#personal-domain)). An exact route takes that name from the first machine, so give its apps names the first doesn't use, e.g. `<app>-<machine>`; the first machine's `*` Access application already covers them. Its own `<host>` and `<machine>` label, so its tailnet names don't clash, and its own API token, so each can be deleted on its own *(docs only)* |
| Mac | The [macOS](#macos) steps, which are untested: work through [To check on a Mac](#to-check-on-a-mac) and correct the guide from what happens |

### The order

1. **Retire Caddy in WSL** (machines with WSL): pull WSL's clone first (`git -C ~/.dotfiles pull`), as `update.ps1` runs its retire steps before it pulls; then run `pwsh ./update.ps1` in WSL, whose retire steps remove an apt-installed Caddy and the low-ports sysctl ([linux/README.md](../linux/README.md#caddy)). *Check:* `pwsh ./update.ps1 -WhatIf` prints `- Caddy is not installed` and `- The low-ports sysctl is not set`.
2. **The dev proxy:** [Windows](#windows-also-windows--wsl) steps 1–8, with the [hardened set-up](#optional-the-hardened-set-up) in place of steps 2–3 and 5 if chosen. *Check:* `https://<app>.localhost` loads in a browser with no certificate warning, and hot reload works.
3. **Clean up the old Caddy:** [old roots, the per-user Caddy and WSL's roots](#optional-clean-up-the-old-caddy). *Check:* `certutil -user -store Root` shows one *Caddy Local Authority* root, the service's.
4. **Tunnels:** install `cloudflared` ([Tunnels](#tunnels)), then the personal domain's tunnel or the person's work tunnel. *Check:* `curl.exe -s -o NUL -w "%{http_code}" https://<public name>/` prints `302` (the Access login), and after the login the page loads.
5. **Tailscale** (personal machines): [tailscale/README.md](../tailscale/README.md), from Windows to the tailnet names. *Check:* the phone opens `https://<app>.<machine>.<personal domain>` with Tailscale connected, and not with it disconnected.
6. **Restart Windows.** *Check:* with `start= auto`, the `caddy` service is running without being started by hand and `https://<app>.localhost` answers; `tailscale serve status` lists the forwards; the tunnel runs again with the same command (nothing starts it by itself); the phone reaches WSL once WSL is running ([Keep WSL running](../tailscale/README.md#keep-wsl-running)).

### When something differs from the guide

The guide is the record, so fix it as you go: rewrite a step that didn't work as written, and relabel a *docs only* step that now worked as *tested*, saying what it was tested on if that differs from the labels at the top.

## Windows (also Windows + WSL)

Commands marked "as administrator" run in PowerShell 7 (`pwsh`) opened with *Run as administrator*. Everything else runs in an ordinary terminal.

1. **Install Caddy machine-wide** *(tested)*.
   - **Where it comes from:** the Windows zip and its checksums file from [Caddy's GitHub releases](https://github.com/caddyserver/caddy/releases) (linked from [Install](https://caddyserver.com/docs/install)).
   - **How:** as administrator, check the zip's SHA-512, then expand it into a folder only administrators can write to. Use the latest release's version in the file names, and only expand the zip if the two hashes match ([Get-FileHash](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash), [Expand-Archive](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.archive/expand-archive)):

     ```powershell
     cd $env:USERPROFILE\Downloads
     Invoke-WebRequest https://github.com/caddyserver/caddy/releases/download/v2.11.9/caddy_2.11.9_windows_amd64.zip -OutFile caddy_2.11.9_windows_amd64.zip
     Invoke-WebRequest https://github.com/caddyserver/caddy/releases/download/v2.11.9/caddy_2.11.9_checksums.txt -OutFile caddy_2.11.9_checksums.txt
     (Get-FileHash caddy_2.11.9_windows_amd64.zip -Algorithm SHA512).Hash
     Select-String windows_amd64.zip caddy_2.11.9_checksums.txt
     New-Item -ItemType Directory 'C:\Program Files\Caddy'
     Expand-Archive caddy_2.11.9_windows_amd64.zip -DestinationPath 'C:\Program Files\Caddy'
     ```

   - **Not a per-user install** (such as winget's default): the user can overwrite that file, and the service would run it as SYSTEM.
   - **Updating** *(docs only)*: download the newer zip and checksums and compare the hashes as above. Then, as administrator, stop the service, expand the zip over the old files with `-Force`, and start it again, with the new version in place of `2.11.9`. A running `caddy.exe` can't be replaced, and without `-Force`, `Expand-Archive` stops at the existing file:

     ```powershell
     sc.exe stop caddy
     Expand-Archive caddy_2.11.9_windows_amd64.zip -DestinationPath 'C:\Program Files\Caddy' -Force
     sc.exe start caddy
     ```

     With Caddy's Cloudflare plugin added for [Tailscale names](../tailscale/README.md#dev-servers-by-name-on-the-tailnet), use `caddy upgrade` instead ([caddy upgrade](https://caddyserver.com/docs/command-line#caddy-upgrade)): the zip has no plugins, so the tailnet site would fail to load and take every site down with it.
2. **Create the configuration** *(tested)*.
   - **Files:** as administrator, create `C:\ProgramData\Caddy\sites`, then copy in the top [Caddyfile](./Caddyfile) and [sites/ports.caddy](./sites/ports.caddy) from this repo's clone ([New-Item](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-item), [Copy-Item](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/copy-item)):

     ```powershell
     New-Item -ItemType Directory C:\ProgramData\Caddy\sites
     Copy-Item $env:USERPROFILE\.dotfiles\dev-proxy\Caddyfile C:\ProgramData\Caddy\
     Copy-Item $env:USERPROFILE\.dotfiles\dev-proxy\sites\ports.caddy C:\ProgramData\Caddy\sites\
     ```

     For a clone elsewhere, change `$env:USERPROFILE\.dotfiles` to its folder. `ports.caddy` is optional (step 7).
   - **What the top file sets** ([global options](https://caddyserver.com/docs/caddyfile/options)):
     - **`default_bind 127.0.0.1 [::1]`** keeps every site, and the HTTP-to-HTTPS redirect server, on loopback, so dev servers aren't exposed to the network.
     - **`skip_install_trust`** stops the service's failed attempts, at every start, to install its root into a trust store ("failed to install root certificate"). Trusting is its own step (5).
     - **`trusted_proxies static 127.0.0.1/32 ::1/128`** is there because tunnels point at Caddy. Without it, Caddy replaces the headers `cloudflared` sends, so the app sees `X-Forwarded-Proto: http` and `X-Forwarded-For: 127.0.0.1` ([reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)).
     - **`import sites/*.caddy`** reads every file in `sites`. An empty match isn't an error, and an imported file can't hold global options ([import](https://caddyserver.com/docs/caddyfile/directives/import)). Sites written straight into the top file work alongside imported ones.
   - **Editing in Notepad:** it adds `.txt` to a name without an extension, so in the Save dialog set *Save as type* to *All files*.
   - **"Caddyfile input is not formatted"** means tabs and spaces are mixed. It's harmless, and [`caddy fmt --overwrite <file>`](https://caddyserver.com/docs/command-line#caddy-fmt) tidies the file.
3. **Create the service** *(tested)*.
   - **Commands,** as administrator ([Running Caddy](https://caddyserver.com/docs/running), "Windows service"; [sc create](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/sc-create)):

     ```powershell
     sc.exe create caddy start= demand binPath= '"C:\Program Files\Caddy\caddy.exe" run --config C:\ProgramData\Caddy\Caddyfile'
     sc.exe start caddy
     ```

   - **Other shells:** only PowerShell 7 was tested. Windows PowerShell 5.1 is expected to mangle the inner quotes. In Command Prompt the line would be (*not tested*):

     ```bat
     sc.exe create caddy start= demand binPath= "\"C:\Program Files\Caddy\caddy.exe\" run --config C:\ProgramData\Caddy\Caddyfile"
     ```

   - **`--config`** is needed because a service starts in `C:\Windows\System32`.
   - **`start= demand`** starts it only when asked, so after a restart it waits for `sc.exe start caddy`. That keeps it from competing with IIS at boot ([If you also use IIS](#if-you-also-use-iis)). Without IIS, use `start= auto` instead, so it starts with Windows: after a Windows restart it was running by the time of login, with nothing started by hand, and its local, tunnel and tailnet names worked *(tested, with the hardened set-up)*.
   - **Data:** the service keeps its data, including its certificate authority's private key, in `C:\Windows\System32\config\systemprofile\AppData\Roaming\Caddy`.
   - **Starting and stopping** (`sc.exe start caddy`, `sc.exe stop caddy`) need administrator rights.
   - **Logs:** a Windows service's output goes nowhere. To see Caddy's log while setting up, add this inside the top file's global options block, restart the service, and remove it afterwards (Caddy rejects it written on one line):

     ```
     	log {
     		output file C:/ProgramData/Caddy/caddy.log
     	}
     ```

4. **Add a project's sites** *(tested)*.
   - **One file per project** in `sites`, named `<project>.caddy`. Start it from [example.caddy](./example.caddy): copy it into `C:\ProgramData\Caddy\sites\<project>.caddy`, then change the names and the upstream port. It holds the project's local name and, if it has one, its public name, with upstreams on `127.0.0.1`:

     ```
     myapp.localhost {
     	reverse_proxy 127.0.0.1:3000
     }

     # The public name, reached through the person's tunnel
     http://person-myapp.example.com:5399 {
     	reverse_proxy 127.0.0.1:3000
     }
     ```

   - **The public name is a plain-HTTP site on a port of its own,** so Caddy doesn't try to get a public certificate for it ([addresses](https://caddyserver.com/docs/caddyfile/concepts#addresses)), and the port isn't IIS's 80. One port, `5399`, serves every public name, as Caddy routes by name. Leave the public site out until the project has a tunnel ([Tunnels](#tunnels)).
   - **Reload** from an ordinary terminal. Windows services can't be reloaded the usual way ([Running Caddy](https://caddyserver.com/docs/running)), and this goes through Caddy's admin API instead ([caddy reload](https://caddyserver.com/docs/command-line#caddy-reload)):

     ```powershell
     & 'C:\Program Files\Caddy\caddy.exe' reload --config C:\ProgramData\Caddy\Caddyfile
     ```

   - **A stopped dev server** behind a working site returns `502` until it's started again. A request with a Host no site matches gets an empty `200`.
5. **Trust Caddy's certificate authority** *(tested)*.
   - **Command:** with the service running, as administrator: `& 'C:\Program Files\Caddy\caddy.exe' trust` ([caddy trust](https://caddyserver.com/docs/command-line#caddy-trust)).
   - **What it does:** it fetches the root from the admin API and installs it into the **current user's** Trusted Root Certification Authorities, even when run as administrator, after a Windows security dialog. Chrome then accepts the certificates (Edge and Firefox weren't tried).
   - **Run it as the account you browse with:** elevating with a separate administrator account would put the root in that account's store. Whether it works without elevation wasn't tested. Where administrator rights come from a separate account, trust it as the [hardened set-up](#optional-the-hardened-set-up) does (step 4): copy `root.crt` out with the administrator account, then add it with `certutil -user` as yourself *(tested, with one account)*.
   - **To remove it:** see [Removing](#removing).
6. **Make `.localhost` names resolve for tools other than browsers** *(tested)*.
   - **Browsers** resolve any `*.localhost` name to the local machine themselves; Windows' own resolver doesn't.
   - **The hosts file:** as administrator, add each name to `C:\Windows\System32\drivers\etc\hosts`, e.g. `127.0.0.1 myapp.localhost`.
   - **Windows' own `curl.exe`** resolves `.localhost` names itself, with no hosts entry, but rejects Caddy's certificates (`CRYPT_E_NO_REVOCATION_CHECK`), as it checks for revocation and Caddy's local authority can't answer that. Use `curl.exe --ssl-no-revoke https://myapp.localhost`.
7. **A name for any port** *(tested, optional)*.
   - **The site:** [sites/ports.caddy](./sites/ports.caddy), copied in step 2, lets `5173.port.localhost` reach `127.0.0.1:5173`, for ports on an allowed list only. Delete it from `sites` and reload if you don't want it.
   - **`{labels.2}`** is the third label counting from the right, starting at 0 ([caddyhttp package docs](https://pkg.go.dev/github.com/caddyserver/caddy/v2/modules/caddyhttp); [reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy), "Upstream addresses").
   - **What it returns:** an allowed port with a server returns its page; an allowed port with nothing on it returns `502`; a port not on the list returns `403`. Chrome accepts the wildcard certificate.
   - **The allowed list:** keep it to ports any `*.port.localhost` page may reach, and never add `2019`, the admin API.
8. **Dev servers** *(tested with Vite and Next)*.
   - **Behind Caddy on a `.localhost` name,** neither needs a change, and hot reload works. [Vite's `server.allowedHosts`](https://vite.dev/config/server-options#server-allowedhosts) allows names under `.localhost` by default, and [Next's `allowedDevOrigins`](https://nextjs.org/docs/app/api-reference/config/next-config-js/allowedDevOrigins) allows `localhost` and its subdomains.
   - **Bind dev servers to `127.0.0.1`** (Vite `--host 127.0.0.1`, Next `-H 127.0.0.1`). Sites point at `127.0.0.1`, which Vite's default `localhost` may not listen on, and it keeps them off the network.
   - **A public name has to be added to the host check:**
     - Vite answers `403 Blocked request. This host is not allowed` until the name is in `server.allowedHosts` (a new config file needs a restart);
     - Next serves the page but blocks hot reload until the name is in `allowedDevOrigins`.
9. **Tunnels,** to reach a dev server from other devices: see [Tunnels](#tunnels).
10. **IIS,** if the machine has it: see [If you also use IIS](#if-you-also-use-iis).
11. **Optional clean-up,** if projects used to run `caddy run` themselves: see [Moving a project onto the service](#moving-a-project-onto-the-service).

## Windows + WSL differences

- **Dev servers in WSL** are reached through WSL's localhost forwarding (`localhostForwarding`, on by default in [`.wslconfig`](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)). Sites files point at `127.0.0.1:<port>` exactly as for a Windows dev server *(tested, including hot reload)*.
- **Don't also run Caddy in WSL:** its forwarding would compete for ports 80 and 443, and it forwards a WSL Caddy's admin API to Windows' `127.0.0.1:2019` *(observed)*. This repo's retire steps remove an apt-installed Caddy from WSL ([linux/README.md](../linux/README.md#caddy)).
- **Tools inside WSL can't reach the names** under WSL's default NAT networking *(tested)*. Use the dev server's `localhost:<port>` from WSL.
- **Names in the Windows hosts file resolve in WSL** through WSL's DNS forwarding, but to `127.0.0.1`, which in WSL is WSL's own loopback *(observed)*. Other `.localhost` names resolve only in `curl`, which handles them itself.
- **Mirrored networking** ([WSL networking](https://learn.microsoft.com/en-us/windows/wsl/networking)) would let tools in WSL reach the Windows Caddy on `127.0.0.1`. In exchange, Windows and WSL share one set of ports, and Docker Desktop's behaviour in that mode is undocumented, so it isn't used here *(docs only)*.

## Tunnels

Two ways to reach a dev server from other devices, by how long the access is needed:

- **One-off sharing** (testing a webhook, letting someone take a look): a [quick tunnel](#one-off-sharing-a-quick-tunnel) straight at the dev server, with no account, admin, Caddy or project change.
- **Regular access** (a stable name, behind a login): a [named tunnel](#regular-access-a-named-tunnel) for each person, which an admin sets up once ([Admin's guide](#admins-guide-cloudflare-tunnel)), with a route for each app. On your own domain you're the admin: see [Personal domain](#personal-domain).

Both use `cloudflared`. Install it with winget, in an ordinary terminal: `winget install --id Cloudflare.cloudflared` *(tested; not in Cloudflare's docs, which link the installer)*. The package installs the 64-bit MSI from Cloudflare's GitHub releases, the one the [downloads page](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/) links, and winget checks its hash. The MSI installs for all users, into `C:\Program Files (x86)\cloudflared`, so it asks for elevation; a terminal opened afterwards finds it on `PATH`. `cloudflared` doesn't update itself on Windows, so run `winget upgrade --id Cloudflare.cloudflared` now and then.

The Cloudflare pages linked in this guide were checked on 2026-11-15.

### One-off sharing: a quick tunnel

*Tested* with a Vite dev server, opened from a phone on mobile data, with and without `--allowed-mail` ([Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)).

- **Command,** in an ordinary terminal, stopped with Ctrl+C:

  ```powershell
  cloudflared tunnel --url http://127.0.0.1:3000 --http-host-header localhost:3000
  ```

- **What you get:** a random `https://<words>.trycloudflare.com` URL, printed in the output. It needs no account, it stops working when `cloudflared` stops, and a new one comes with every run.
- **`--http-host-header`** sends each request in with the Host the dev server expects, so its host check passes with no project change ([origin parameters](https://developers.cloudflare.com/tunnel/reference/origin-parameters/#httphostheader)). Links the app builds from the Host come out as `localhost:3000`, which a visitor can't open.
- **Point it at the dev server:** a quick tunnel has one `--url`, so going through Caddy adds nothing.
- **A login in front:** `--allowed-mail <email>` makes visitors enter their email address and a one-time PIN first. Repeat it, or give a comma-separated list, for several people; `'*@example.com'` allows a whole domain (quoted, so the shell leaves the `*` alone). It needs an interactive browser, so it doesn't suit webhooks. Refreshing the page asked for the email and PIN again *(observed, Chrome on Android)*, where a named tunnel's Access login lasts through a refresh; the docs don't say how long a quick tunnel's login lasts.
- **Limits:** no uptime guarantee; up to 200 requests in flight, with more getting `429`; no Server-Sent Events.
- **Not in official docs:** a `config.yml` in `%USERPROFILE%\.cloudflared` can stop quick tunnels from working ([an article](https://flaviocopes.com/cloudflare-quick-tunnels/)).
- **Risks:**
  - without `--allowed-mail`, anyone with the URL can reach that port, so stop it when done, and use a webhook's signature checks;
  - the name changes on every run, so a webhook's registration needs updating each time;
  - there's no account behind it, so nothing records who opened it.
- **Whether to use them:** where several people use this set-up under one organisation, whether quick tunnels are allowed is that organisation's call, so check first.

### Regular access: a named tunnel

*Tested,* now including the install. Each person runs their own tunnel, which an admin creates and hands them the token for ([Admin's guide](#admins-guide-cloudflare-tunnel)). Every route on it points at Caddy's public-name port, `5399`, and Caddy routes each name to its dev server.

1. **The token file:** keep the token in a file only you can read, e.g. `%USERPROFILE%\.cloudflared\<tunnel>.token`. Paste it into Notepad and save it there (*Save as type*: *All files*); never paste it into a terminal or a chat.
2. **Run it** in an ordinary terminal, and stop it with Ctrl+C. It runs only while that terminal is open: nothing starts it at login or after a restart. `--token-file` keeps the token out of shell history and the process list ([run parameters](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/run-parameters/#token-file)):

   ```powershell
   cloudflared tunnel run --token-file "$env:USERPROFILE\.cloudflared\<tunnel>.token"
   ```

3. **The project's public site:** for each app the admin routes to you, add its public name to the project's sites file as a plain-HTTP site on port `5399`, as in [example.caddy](./example.caddy), and reload (step 4), or restart the service with the [hardened set-up](#optional-the-hardened-set-up):

   ```
   http://person-myapp.example.com:5399 {
   	reverse_proxy 127.0.0.1:3000
   }
   ```

4. **The dev server's host check:** add the public name to [Vite's `server.allowedHosts`](https://vite.dev/config/server-options#server-allowedhosts) or [Next's `allowedDevOrigins`](https://nextjs.org/docs/app/api-reference/config/next-config-js/allowedDevOrigins). Until then, Vite answers `403` and Next blocks hot reload (step 8).
5. **What arrives at the app:** the public Host unchanged, `X-Forwarded-Proto: https`, the visitor's address in `X-Forwarded-For` (followed by `127.0.0.1`, the hop from `cloudflared` to Caddy), and the request body. The top file's `trusted_proxies` is what keeps the forwarded headers: without it, Caddy replaces the ones `cloudflared` sends, and the app sees `http` and `127.0.0.1` (step 2).
6. **Error overlays:** a dev server shows error overlays and stack traces to whoever can load the page, so keep Access in front of everything but webhook paths.

To stop using a tunnel, see [Removing](#removing).

### Option: skip the project changes with a Host override

*Tested with a quick tunnel and Vite 7.3.8; the dashboard settings are docs only.* A route can send each request in as the app's `.localhost` name, so the project's local site answers it, with no public site in the sites file and no host-check change. The admin sets this per route, under the route's **Additional application settings** ([origin parameters](https://developers.cloudflare.com/tunnel/reference/origin-parameters/), [HTTPS origins](https://developers.cloudflare.com/tunnel/troubleshooting/https-origins/)):

| Setting | Value |
|---|---|
| Service URL | `https://127.0.0.1:443` |
| HTTP → **HTTP Host Header** | `<app>.localhost` |
| TLS → **Origin Server Name** | `<app>.localhost`, or turn on **Match SNI to host** instead *(not tested)* |
| TLS → **CA Pool** | a copy of Caddy's root, e.g. `C:\Users\<user>\.cloudflared\caddy-root.crt`, with **Disable TLS certificate verification** left off |

- **The CA pool copy:** Caddy's root is readable only by administrators, so copy it as administrator: `Copy-Item C:\Windows\System32\config\systemprofile\AppData\Roaming\Caddy\pki\authorities\local\root.crt C:\Users\<user>\.cloudflared\caddy-root.crt`. Turning on **Disable TLS certificate verification** instead of a CA pool works too, as the connection never leaves the machine, but Cloudflare's guide keeps verification on. Both were tested.
- **The TLS name is required:** without it, requests fail with `502`, as Caddy has no certificate for `127.0.0.1`.
- **What the app sees:** `Host: <app>.localhost`, with the public name in `X-Forwarded-Host`.
- **The catch:** links and callbacks the app builds from the Host come out as `https://<app>.localhost/…`, which a visitor can't open; apps that use `X-Forwarded-Host` get the public name. Sign-in callbacks are the usual casualty, so the public site above stays the default.
- **One route per app:** a route has one Host override, so this doesn't work with the personal domain's wildcard route.
- **Not tested:** a route set up this way in the dashboard, **Match SNI to host**, and Next.

## Admin's guide: Cloudflare Tunnel

For whoever manages the Cloudflare account that holds the domain: setting up each person's tunnel and the login in front of it, and cleaning up when someone leaves. *Tested* in Cloudflare's dashboard on 2026-11-12. Where the docs have changed since, the step follows the docs and is marked *changed in the docs*.

- **Check each step first:** the dashboard changes often, so check every step against current docs before following it, with context7 (`/cloudflare/cloudflare-docs`) or the page's `index.md` (its URL with `index.md` added). This goes for agents too. Where Cloudflare's plugin is installed, agents use it read-only: changes are made by the person, or by an agent with that person's approval for each change.
- **A dedicated account:** a domain used this way lives in a Cloudflare account of its own, so the people and tunnels set up for it can't reach other domains and resources. Tunnels, the Access organisation and its login domain, and anyone invited as an admin are all account-wide. For the work domain this is still to be confirmed.

**Setting up a person:**

1. **Their tunnel** ([create a tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/)): Networking → Tunnels → **Create a tunnel**, named for the person → **Create Tunnel**. Choose their operating system and copy the token from the install command it shows (the long `eyJ…` string); don't run the command. *Changed in the docs:* there's no longer a connector type to choose. To see the token again later, use **Add a replica** on the tunnel's **Overview** tab ([tunnel permissions](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/remote-tunnel-permissions/)).
2. **The token:** hand it over privately, as you would a password. It runs that tunnel and nothing else.
3. **Their Access application, once, before any route** ([publish a self-hosted application](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/), [application paths](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/app-paths/)). One application on `<person>-*` covers every `<person>-<app>` name, so each new route is behind the login from the start *(tested on a personal domain with made-up names)*. *Changed in the docs:* Cloudflare recommends creating the Access application before the route, as a route without one is open to anyone, and the button is **Add public hostname**.
   - **The app:** Zero Trust → Access controls → Applications → **Create new application** → **Self-hosted and private** → **Add public hostname**. Enter the subdomain `<person>-*` on the domain, with no path, and an *Allow* policy, e.g. the person's email address with the one-time PIN login.
   - **What it covers:** any text in place of the `*`, hyphens included (`<person>-my-app`), but not `<person>` alone, and only one level deep.
   - **Person names have no hyphens:** otherwise one person's `chris-*` would also match another's `chris-p-myapp`, and the docs don't say which application wins.
4. **Once per zone: turn on Always Use HTTPS** ([Always Use HTTPS](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/always-use-https/)): SSL/TLS → Edge Certificates → **Always Use HTTPS**. The option is hidden while the encryption mode is *Off*. Without it, a tunnel hostname requested over `http://` is served over plain HTTP *(tested)*.

**Adding an app for them:**

1. **The route** ([create a tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/#2a-publish-an-application)): on their tunnel, the **Routes** tab → **Add route** → **Published application**. Enter the subdomain `<person>-<app>`, choose the domain, and set **Service URL** to `http://127.0.0.1:5399` → **Add route**.
   - **DNS:** Cloudflare creates the hostname's DNS record.
   - **Multi-level names:** a subdomain more than one level deep needs an Advanced Certificate.
   - **The Host override:** see [Option: skip the project changes with a Host override](#option-skip-the-project-changes-with-a-host-override).
2. **An open webhook path,** if the app has one: an Access application for that hostname with the path (e.g. `<person>-<app>` and `webhook`) and a *Bypass* policy for *Everyone* ([policies](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/#bypass)). It takes precedence over the person's `<person>-*` application *(tested)*. Requests through a bypass aren't logged.
   - **Tested:** every other path, including `POST /`, redirects to the login. The bypass covers everything under its path but not lookalikes (`/webhookx`). It **ignores case** (`/Webhook` was open too), and requests through it carry no Access token.
   - **Check the policy's action:** a policy saved as *Allow* by mistake keeps the path behind the login.

**When someone leaves**, in this order:

1. Delete each of their routes, then check DNS → Records for a CNAME left pointing at `…cfargotunnel.com`.
2. Delete their Access applications: the bypass ones first, then their `<person>-*` one.
3. Delete the tunnel, which makes its token useless. It can't be undone ([tunnels FAQ](https://developers.cloudflare.com/cloudflare-one/faq/cloudflare-tunnels-faq/)). *Changed in the docs:* **Refresh token** on the tunnel's Overview isn't enough on its own to cut someone off. It stops new connections with the old token, but a `cloudflared` already connected stays connected until its connections are deleted, which the docs show only through the API ([tunnel permissions](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/remote-tunnel-permissions/#rotate-a-compromised-token)).

**Nobody else runs `cloudflared tunnel login`:** the `cert.pem` it creates lets whoever holds it create, delete and manage every tunnel in the account ([tunnel permissions for locally-managed tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/tunnel-permissions/)).

**Letting people add their own routes** *(docs only, unverified)*. Cloudflare can scope a member's role to one tunnel: Manage Account → Members → their policy → Scope *Specific resources* → resource type *Cloudflare Tunnel instances*, a beta feature ([granular permissions](https://developers.cloudflare.com/tunnel/guides/granular-permissions/), [role scopes](https://developers.cloudflare.com/fundamentals/manage-members/scope/)). What the docs leave open:

- **Routes:** they don't say whether that scope covers adding published application routes.
- **DNS:** routing a tunnel to a public hostname needs the DNS role ([tunnel permissions](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/remote-tunnel-permissions/#account-scoped-roles)), which covers every record on the domain, other people's included.
- **Names:** nothing stops a member routing another person's `<person>-` name.
- **Access:** a new route is covered by the person's `<person>-*` application from the start, but a webhook's Bypass application needs an account-level Access role, so the admin would still add those.

Until the account's admins have tested it, the admin adds every route.

## Personal domain

On your own domain you're the admin, so the [Admin's guide](#admins-guide-cloudflare-tunnel) applies, with one tunnel per machine and one wildcard route in place of a route per app. A new app then needs only its sites-file entry. *Tested,* except where marked: one machine's tunnel, its `*` route and `*` Access application, with a Vite dev server, from a desktop browser.

- **Names:** `<app>.<personal domain>`, e.g. `myapp.example.net`, one level deep so Cloudflare's free certificate covers them.
- **The tunnel:** one per machine, named for it, run as in [Regular access](#regular-access-a-named-tunnel).
- **The wildcard route:** subdomain `*` on the domain → Service URL `http://127.0.0.1:5399`, behind one Access application with subdomain `*`. A `*.example.net` application covers `myapp.example.net`, but not the domain itself or deeper names ([application paths](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/app-paths/)). Webhook paths get their own Bypass applications, one per hostname.
- **A new app:** add `http://<app>.<personal domain>:5399` to the project's sites file, and the name to its host check. On the machine with the `*` route, nothing changes in Cloudflare.
- **The dashboard takes the wildcard route,** though Cloudflare's docs show wildcard hostnames only in a locally-managed tunnel's config file. DNS → Records then shows a proxied `*` record of type *Tunnel*, not a CNAME.
- **What the `*` Access application did** (curl, redirects not followed): `https://<app>.<personal domain>/` returned `302` to the Access login, and so did a name with no site behind it; the bare domain, which has no record, didn't connect; `http://` redirected to `https://` (`301`). After the PIN, the page loaded, a refresh didn't ask again, and hot reload worked. Partial wildcards (e.g. `*-alpha`) matched as the docs describe, and a Bypass application for one hostname's webhook path took precedence over them; a Bypass under the full `*` application wasn't tried.
- **Names with no site** pass the login, then get Caddy's empty `200`, as no site on `5399` matches them *(Caddy's answer tested directly on `5399`)*.
- **A second machine:** give it exact routes per app on its own tunnel. An exact DNS record takes precedence over the wildcard ([wildcard DNS records](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/#specific-dns-records-take-precedence-over-wildcard-records)).
- **Tailscale names** (`<app>.<machine>.<personal domain>`) have their own DNS record: see [tailscale/README.md](../tailscale/README.md).

## macOS

**Untested: nothing here has been run on a Mac.** The steps follow the [Windows steps](#windows-also-windows--wsl) one for one, and each difference says why. Whoever first runs them on a Mac works through [To check on a Mac](#to-check-on-a-mac) and reports back, so the steps can be corrected and scripted from what actually happens. Every step is *docs only*.

`$(brew --prefix)` is `/opt/homebrew` on Apple silicon and `/usr/local` on Intel Macs.

1. **Install Caddy with Homebrew:** `brew install caddy`, updated with `brew upgrade caddy`.
   - **Differs from Windows,** which installs Caddy's official release by hand: Homebrew's formula is what provides the service (step 3).
   - **Status:** Caddy lists Homebrew as a community-maintained install method ([Install](https://caddyserver.com/docs/install)). The formula builds the same release with Caddy's own build tool, `xcaddy` ([formula](https://github.com/Homebrew/homebrew-core/blob/main/Formula/c/caddy.rb)).
   - **The official alternative:** the macOS build on [Caddy's GitHub releases](https://github.com/caddyserver/caddy/releases) (`caddy_<version>_mac_arm64.tar.gz` or `_mac_amd64`), which would need a launchd service written by hand; Caddy's docs don't cover one ([Running Caddy](https://caddyserver.com/docs/running)).
2. **Create the configuration:** copy the top [Caddyfile](./Caddyfile) to `$(brew --prefix)/etc/Caddyfile`, with a `sites` folder beside it holding [sites/ports.caddy](./sites/ports.caddy), so `import sites/*.caddy` works unchanged:

   ```bash
   mkdir -p "$(brew --prefix)/etc/sites"
   cp ~/.dotfiles/dev-proxy/Caddyfile "$(brew --prefix)/etc/"
   cp ~/.dotfiles/dev-proxy/sites/ports.caddy "$(brew --prefix)/etc/sites/"
   ```

   For a clone elsewhere, change `~/.dotfiles` to its folder.

   - **The path is fixed:** the formula's service always reads `$(brew --prefix)/etc/Caddyfile`.
   - **No admin rights needed,** unlike Windows: Homebrew's prefix belongs to the user.
3. **Start the service:** `brew services start caddy` ([brew services](https://docs.brew.sh/Manpage)).
   - **What it does:** it starts Caddy now and at every login, as a launchd agent running as the user, with `caddy run --config $(brew --prefix)/etc/Caddyfile`.
   - **Data,** including the certificate authority's private key, goes in `$(brew --prefix)/var/lib/caddy`, as the formula sets the service's `XDG_DATA_HOME` and `HOME` to `$(brew --prefix)/var/lib`.
   - **The log** is `$(brew --prefix)/var/log/caddy.log`, so no logging block is needed, unlike on Windows.
   - **Starting and stopping:** `brew services stop caddy` and `brew services start caddy`, with no admin rights.
   - **Differs from Windows,** which runs Caddy as a system service: running as the user is the closest equivalent that needs no root, and anything that can reach the admin API can then only do what the user already can.
   - **The fallback, only if the check fails:** if Caddy running as the user can't bind ports 80 and 443 on `127.0.0.1` ([check 1](#to-check-on-a-mac)), use `sudo brew services start caddy` instead. That runs Caddy as root from boot, like Windows, with the admin-API risk that comes with it. Homebrew warns: "Only use `sudo` if you trust the prefix owner and the service software."
4. **Add a project's sites:** the same files as on Windows, in `$(brew --prefix)/etc/sites`, then reload from any terminal, through the admin API as on Windows ([caddy reload](https://caddyserver.com/docs/command-line#caddy-reload)):

   ```bash
   caddy reload --config "$(brew --prefix)/etc/Caddyfile"
   ```

5. **Trust Caddy's certificate authority:** with the service running, `caddy trust`, or `sudo caddy trust` if that fails ([caddy trust](https://caddyserver.com/docs/command-line#caddy-trust); the docs say it "may need" `sudo` on Unix systems).
   - **How:** as on Windows, it fetches the root from the admin API, so it doesn't matter where the service keeps its data.
   - **Where it goes:** Caddy's docs don't say which macOS store; the System keychain, with a password prompt, is expected (check 3).
6. **Make `.localhost` names resolve for tools other than browsers:** add each name to `/etc/hosts`, e.g. `127.0.0.1 myapp.localhost`, editing it with `sudo`. Whether macOS's own resolver handles `.localhost` without an entry isn't documented (check 4), and Safari is reported to rely on it.
7. **A name for any port:** the same `sites/ports.caddy` as on Windows.
8. **Dev servers:** the same as on Windows: bind to `127.0.0.1`, and add any public name to the host check.
9. **Tunnels:** as in [Tunnels](#tunnels), with these differences.
   - **Install `cloudflared`:** `brew install cloudflared` ([downloads page](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/)), updated with `brew upgrade`, as winget updates it on Windows.
   - **The token file** is `~/.cloudflared/<tunnel>.token`:

     ```bash
     cloudflared tunnel run --token-file ~/.cloudflared/<tunnel>.token
     ```

   - **Who can read it:** a Windows user's profile is private to them. Whether other accounts on the same Mac can read `~/.cloudflared` depends on the home folder's permissions, which isn't confirmed (check 6).
   - **The Host override's CA pool** can point straight at `$(brew --prefix)/var/lib/caddy/pki/authorities/local/root.crt`, as the service's data belongs to the user. With the `sudo` fallback, it belongs to root instead.
10. **IIS:** not applicable.
11. **Optional clean-up** after moving from per-project `caddy run`:
    - **What's left:** old *Caddy Local Authority* roots in the keychain. Remove them in Keychain Access, or with `caddy untrust --cert <old root.crt>` while the old file still exists.
    - **Where the old files are:** per-user `caddy run` keeps its data in `~/Library/Application Support/Caddy` ([conventions](https://caddyserver.com/docs/conventions#data-directory)).

### To check on a Mac

Run through the steps above, then report on each:

1. **Ports:** with `brew services start caddy` (not `sudo`), does Caddy bind `127.0.0.1:443` and `127.0.0.1:80` with `default_bind 127.0.0.1 [::1]`?
   - **Check:** `brew services list`, the log, and `lsof -nP -iTCP -sTCP:LISTEN | grep caddy`.
   - **Why it's open:** Apple engineers say macOS stopped requiring root for ports below 1024 in Mojave; later forum replies say binding one specific address still needs root ([Apple Developer Forums](https://developer.apple.com/forums/thread/674179)). If it fails, try the `sudo` fallback in step 3 and say what changed.
2. **Firewall prompt:** does macOS's application firewall prompt when the service starts?
3. **`caddy trust`:** which keychain does it use, does it need `sudo`, and do Safari, Chrome and Firefox then accept `https://myapp.localhost` without a warning?
4. **Names without a hosts entry:** does `curl https://myapp.localhost` work, and does Node's `dns.lookup` resolve the name? Does Safari need a hosts entry?
5. **Dev servers:** a Vite and a Next dev server behind Caddy. Do hot reload and the port wildcard work?
6. **The token file:** who can read `~/.cloudflared`? Check with `ls -la ~/.cloudflared`.
7. **Tunnels:** a quick tunnel and, if the admin sets one up, the person's named tunnel through Caddy.
8. **After a restart:** does Caddy come back at login (or at boot with the `sudo` fallback)?
9. **Removing:** follow [Removing](#removing) for macOS, then say whether anything was left behind.

## If you also use IIS

IIS holds ports 80 and 443 on every address, so IIS and Caddy take turns *(tested)*. As administrator:

```powershell
# Caddy on
iisreset /stop
sc.exe start caddy
# IIS back
sc.exe stop caddy
iisreset /start
```

- **What `iisreset /stop` does:** it stops W3SVC and WAS and frees both ports, but leaves the HTTP service (HTTP.sys) running, so the Print Spooler, SSDP Discovery, WinRM and the other services that depend on it carry on.
- **Start types aren't changed,** so this lasts until the next restart. *Not in official docs:* no current Microsoft page for `iisreset` was found; `iisreset /?` lists its options.

Two ways to run both at once were assessed, not tried. Moving HTTP.sys to another loopback address (`netsh http add iplisten 127.0.0.2`) applies to every HTTP.sys user, not just IIS, needs every IIS site's hosts entries changed, can't move an IIS site on a `.localhost` name, and Microsoft's pages don't say whether it needs the HTTP service restarted (which stops the Print Spooler and others); it's worth a trial of its own if switching by hand becomes a nuisance. Putting Caddy in front of IIS would move every IIS site's bindings and break Windows authentication and apps that build URLs from what they see, so it's the most work to set up and undo.

## Moving a project onto the service

For a project that used to run `caddy run` with its own Caddyfile. These come from moving scratch Vite and Next projects in testing *(tested, except where marked)*; no real project has been moved yet.

- **Its sites file:** the project's site blocks as they are, with upstreams on `127.0.0.1:<port>` instead of `localhost:<port>`. `header_up Host {upstream_hostport}` can stay.
- **Its global options go.** The common ones aren't needed:
  - **`http_port 80` and `https_port 443`** are Caddy's defaults.
  - **`local_certs`** would make every site on the machine use Caddy's own authority, which `.localhost` names already do.
  - **`auto_https disable_redirects`** in the shared top file would turn off redirects for every project. A plain-HTTP site is served over HTTP whatever that setting is *(docs only)* ([addresses](https://caddyserver.com/docs/caddyfile/concepts#addresses)).
- **`file_server` alongside `reverse_proxy`** never runs, as `reverse_proxy` comes first in Caddy's [directive order](https://caddyserver.com/docs/caddyfile/directives#directive-order) and handles every request. Check what it was meant for before removing it.
- **Scripts that start the dev server and `caddy run` together** go; the project's script for the dev server alone starts it.
- **The project's docs** about its own Caddy point at this guide instead.
- **Two projects with the same upstream port** still can't run at the same time.

### Optional: clean up the old Caddy

Per-project `caddy run` leaves things the service doesn't use. Removing them is optional *(docs only, except where marked)*.

- **Old roots on Windows:** each Caddy that ran as you made its own *Caddy Local Authority* root in your Trusted Root Certification Authorities. Keep the service's own root, which `caddy trust` installed in step 5 ([certutil](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil)):
  1. as administrator, find the service root's thumbprint, the `Cert Hash(sha1)` line of `certutil -dump C:\Windows\System32\config\systemprofile\AppData\Roaming\Caddy\pki\authorities\local\root.crt`;
  2. in an ordinary terminal, `certutil -user -store Root` lists your roots, each with its `Subject` and `Cert Hash(sha1)`;
  3. for each *Caddy Local Authority* root with a different hash, `certutil -user -delstore Root <thumbprint>` *(tested)*, confirming the Windows dialog.
- **The per-user Caddy on Windows:** `winget uninstall --id CaddyServer.Caddy` if winget installed it ([winget uninstall](https://learn.microsoft.com/en-us/windows/package-manager/winget/uninstall)), or `choco uninstall caddy -y` as administrator if Chocolatey did *(tested)*, then delete its data folder, `%APPDATA%\Caddy` ([conventions](https://caddyserver.com/docs/conventions#data-directory)). Afterwards `caddy` alone isn't on `PATH`, so run the service's copy by its full path, as this guide does.
- **Old roots in WSL:** WSL's Caddy put its roots in `/usr/local/share/ca-certificates/Caddy_Local_Authority_-_*.crt`. With Caddy gone from WSL, delete them and rebuild the trust store's links ([update-ca-certificates](https://manpages.debian.org/stable/ca-certificates/update-ca-certificates.8.en.html)):

  ```bash
  sudo rm /usr/local/share/ca-certificates/Caddy_Local_Authority_-_*.crt
  sudo update-ca-certificates --fresh
  ```

  `--fresh` also removes dangling links that `caddy untrust` leaves in `/etc/ssl/certs` *(tested)*.

## Optional: the hardened set-up

The set-up above runs Caddy as the trial did, and accepts a risk: any local process can reconfigure Caddy through its admin API on `127.0.0.1:2019`, and ordinary users can probably add sites files, as `C:\ProgramData` lets them create files. Whether either is likely to be exploited is unclear. The hardened set-up turns the admin API off and keeps the config where only administrators can write *(tested)*. The cost: every change needs an administrator to restart the service, and trusting the root is done by hand.

1. **The config,** under `C:\Program Files\Caddy\` beside `caddy.exe` (installed in [step 1](#windows-also-windows--wsl)), in place of step 2's: the top `Caddyfile`, with `admin off` added to its global options block ([admin](https://caddyserver.com/docs/caddyfile/options#admin)), and the `sites` folder. As administrator:

   ```powershell
   New-Item -ItemType Directory 'C:\Program Files\Caddy\sites'
   Copy-Item $env:USERPROFILE\.dotfiles\dev-proxy\Caddyfile 'C:\Program Files\Caddy\'
   Copy-Item $env:USERPROFILE\.dotfiles\dev-proxy\sites\ports.caddy 'C:\Program Files\Caddy\sites\'
   $f = 'C:\Program Files\Caddy\Caddyfile'
   Set-Content $f ((Get-Content $f -Raw) -replace '^\{\r?\n', "{`n`tadmin off`n") -NoNewline
   Select-String 'admin off' $f
   ```

   - **The last line** shows `admin off` if it went in; with no output, add it by hand as the first line inside the opening `{`.
   - **A project's sites file** goes in `C:\Program Files\Caddy\sites\`, written as administrator (e.g. Notepad run as administrator).
   - **For a log,** use `output file "C:/Program Files/Caddy/caddy.log"` in step 3's logging block, quoted because of the space.
2. **The service,** as administrator. If the default service already exists, remove it first with `sc.exe stop caddy; sc.exe delete caddy` ([sc delete](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/sc-delete)). The config path is quoted because of the space, and without IIS `start= auto` replaces `start= demand`, as in step 3:

   ```powershell
   sc.exe create caddy start= demand binPath= '"C:\Program Files\Caddy\caddy.exe" run --config "C:\Program Files\Caddy\Caddyfile"'
   sc.exe start caddy
   ```

   Only PowerShell 7 was tested. In Command Prompt the line would be (*not tested*):

   ```bat
   sc.exe create caddy start= demand binPath= "\"C:\Program Files\Caddy\caddy.exe\" run --config \"C:\Program Files\Caddy\Caddyfile\""
   ```

3. **Changes** apply after `sc.exe stop caddy; sc.exe start caddy` as administrator. `caddy reload` fails with "connection refused", as nothing listens on 2019.
4. **Trusting it:** `caddy trust` needs the admin API, and the root certificate is only readable by administrators. So copy it out as administrator, then add it in an ordinary terminal, confirming the Windows dialog ([certutil](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil)):

   ```powershell
   # As administrator
   Copy-Item C:\Windows\System32\config\systemprofile\AppData\Roaming\Caddy\pki\authorities\local\root.crt C:\Users\<user>\Downloads\caddy-root.crt
   # As yourself
   certutil -user -addstore Root $env:USERPROFILE\Downloads\caddy-root.crt
   ```

What the tests showed, the second time on a first install with `start= auto`: nothing listens on 2019 and the log says "admin endpoint disabled"; an ordinary user creating a file in `sites` gets "Access … is denied", as Users can only read it; and Chrome loads the sites with no warning, with hot reload working.

## Optional: DNS filters

Some steps in these guides exist only because of a DNS filter, such as NextDNS. Each is labelled *optional* and says when it applies; without a filter, none of them is needed.

- **The Windows dev proxy on its own:** nothing applies. `.localhost` names never leave the machine.
- **macOS:** the same as Windows: nothing applies.
- **Tunnels:** nothing applies either, as tunnel names point at Cloudflare's public addresses.

## Removing

**On Windows,** as administrator unless a step says otherwise. The steps are *docs only* except where marked *tested*.

1. **The root,** in an ordinary terminal: `certutil -user -store Root` lists your roots; find *Caddy Local Authority* in a `Subject` line, then run `certutil -user -delstore Root <thumbprint>` with its `Cert Hash(sha1)` value *(tested)*, confirming the Windows dialog ([certutil](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil)). `caddy untrust` does the same while the service is still running, as it uses the admin API ([caddy untrust](https://caddyserver.com/docs/command-line#caddy-untrust)). PowerShell's `Remove-Item Cert:\CurrentUser\Root\<thumbprint>` fails with "The operation is on user root store and UI is not allowed".
2. **The service:** `sc.exe stop caddy; sc.exe delete caddy` ([sc delete](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/sc-delete)).
3. **Caddy and its config:** delete `C:\Program Files\Caddy`, and `C:\ProgramData\Caddy` unless you used the hardened set-up.
4. **The service's data:** delete `C:\Windows\System32\config\systemprofile\AppData\Roaming\Caddy`, which holds the certificate authority's private key.
5. **Hosts entries:** remove the names added to `C:\Windows\System32\drivers\etc\hosts` in set-up step 6.
6. **A tunnel,** in an ordinary terminal *(docs only)*:
   - stop `cloudflared` with Ctrl+C;
   - delete the token file, `%USERPROFILE%\.cloudflared\<tunnel>.token`, and `caddy-root.crt` beside it if you made one for the Host override;
   - remove the public sites from the projects' sites files, and the public names from their host checks;
   - uninstall `cloudflared` with `winget uninstall --id Cloudflare.cloudflared`, if it's no longer wanted ([winget uninstall](https://learn.microsoft.com/en-us/windows/package-manager/winget/uninstall));
   - the admin deletes the tunnel, its routes and its Access applications ([When someone leaves](#admins-guide-cloudflare-tunnel)).

**On macOS** *(docs only)*:

1. **The root,** while the service still runs, as `caddy untrust` uses the admin API: `caddy untrust`, or `sudo caddy untrust` if trusting needed `sudo` ([caddy untrust](https://caddyserver.com/docs/command-line#caddy-untrust)).
2. **The service:** `brew services stop caddy` (with `sudo` if it was started with `sudo`).
3. **Caddy's config and data:** delete `$(brew --prefix)/etc/Caddyfile`, the `sites` folder beside it, and `$(brew --prefix)/var/lib/caddy`, which holds the certificate authority's private key.
4. **Hosts entries:** remove the names added to `/etc/hosts` in set-up step 6, with `sudo`.
5. **A tunnel:** stop `cloudflared`, delete `~/.cloudflared/<tunnel>.token`, and remove the public sites and host-check names, as on Windows; the admin deletes the tunnel.
6. **The tools:** `brew uninstall caddy cloudflared`.

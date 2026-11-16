# Dev proxy: design (draft)

**Status:** built as reference docs (2026-11-16): see [Where things stand](#where-things-stand). The items under [Still open](#still-open) that aren't marked decided or tested remain. Names marked *provisional* may still change. The work is tracked in the [project plan](../plans/2026-11-14-dev-proxy-project.md).

**Started:** 2026-11-11 as "service names on your own domain". **Updated:** 2026-11-14: portless dropped after the work-machine Caddy trial; first pass of decisions; named "dev proxy". 2026-11-16: built, per the [implementation plan](../plans/2026-11-14-dev-proxy-implementation.md).

## Where things stand

### Built (2026-11-16)

The [implementation plan](../plans/2026-11-14-dev-proxy-implementation.md) is done:

- **[dev-proxy/README.md](../../../dev-proxy/README.md):** the Windows (and Windows + WSL) guide, the tunnel guides (quick tunnels, named tunnels, the Host override option, the admin's guide, the personal domain), the untested macOS guide with its checklist, IIS, moving a project over, the hardened set-up, DNS filters and removing. Its config files are beside it: `Caddyfile`, `sites/ports.caddy` and `example.caddy`.
- **[tailscale/README.md](../../../tailscale/README.md):** Tailscale on Windows only, SSH to WSL through a forwarded port, and dev servers by name on the tailnet, with `tailscale/tailnet.caddy`.
- **WSL:** `install.ps1` no longer installs Caddy or sets the low-ports sysctl, and retire steps remove both.
- **The exploration's script** (`tailscale.ps1`, its module and tests) is gone.

The sections below record how things stood before that.

### 1. Tailscale (exploration, on a branch)

An opt-in Tailscale setup is committed on `feature/tailscale`: `tailscale.ps1`, `lib/Tailscale.psm1`, `tests/Tailscale.Tests.ps1`, `tailscale/README.md`, plus links from `AGENTS.md`, `README.md`, `linux/README.md` and `windows/README.md`. Windows and WSL join the tailnet as two devices: WSL (`meeg-laptop-wsl`) with Tailscale SSH, Windows (`meeg-laptop`) with its OpenSSH server limited to tailnet addresses.

It was exploration that got ahead of this design, and was reviewed against it on 2026-11-14 (project plan, step 4). With Tailscale now on Windows only, the script, module and tests are to be removed and the README rewritten. The changes go into the implementation plan; don't run the script meanwhile.

### 2. Work-machine Caddy trial (done)

A trial on the work machine replaced per-project `caddy run` with one always-on Caddy, and tried Cloudflare Tunnel for public names. Its brief (`2026-11-11-caddy-service-trial.md`) and report (`2026-11-11-caddy-service-trial-report.md`) replaced the portless brief (`2026-11-11-portless-trial-brief.md`), which was never run. Its findings are summarised under [What the work trial established](#what-the-work-trial-established).

Their content was folded into this design on 2026-11-14 (mainly [Set-up as tested](#set-up-as-tested)), leaving out anything about specific work projects. Once that's reviewed, the brief, the report and the portless brief are deleted from this repo.

## Goal

A set-up that works for the team on Windows (including Windows + WSL) and macOS, with optional extras for personal machines:

- every project's dev server has a name, never a port number, both on the machine itself and from other devices;
- names from other devices are on a domain you control, so they don't depend on Tailscale's or the tailnet's names;
- one-off dev servers can get a name with no setup.

The same dotfiles run on the personal laptop and the work laptop. The default parts apply to both; the personal parts (Tailscale and its route) are optional, used on the personal laptop and not on the work one.

**herdr and SSH** (clarified 2026-11-14):

- **Without Tailscale:** the Herdr app and SSH set-up keep working exactly as they do today. The Windows Herdr app reaches each WSL distro over SSH on `127.0.0.1:<port>` (`linux/README.md` → Herdr app (Windows → WSL)). Nothing in this project changes that; retiring Caddy in WSL doesn't touch WSL's SSH server, whose port (2222) needs no low-ports setting.
- **With Tailscale:** the set-up may change, but it must keep two things working:
  - the Windows Herdr app reaching the host's WSL distro or distros locally;
  - from other devices, reaching the Windows host and each of its WSL distros.

  Both work with Tailscale on Windows only (see [Decisions](#reaching-dev-servers-from-other-devices)): the Windows app's local link is untouched, the Windows host is reached on port 22, and each distro on its own forwarded port.
- **More than one WSL distro:** all WSL 2 distros share one VM and one network. That comes from a Microsoft maintainer in [WSL issue #4304](https://github.com/microsoft/WSL/issues/4304); Microsoft's docs don't say it outright. So each distro's SSH server needs its own port (2222, 2223, …), each forwarded by Windows' Tailscale.

## Decisions

### Shape

- **Not `tailscale serve` alone:** it gives each device one name, so a second service needs a port (`--https=8443`) or a path (`--set-path=/api`), and paths break apps that expect to be served from `/`. Tailscale Services give per-service names but need a tagged device, which takes it out of your personal devices.
- **portless is dropped (2026-11-14).** This replaces the earlier decision that portless would sit behind Caddy and route names to one-off dev servers. Discussing the work trial showed it isn't needed alongside an always-on Caddy, and adds more than it gives.
- **Caddy serves every name, as an always-on service.**
  - **Windows** (including Windows + WSL): a Windows service. It reaches dev servers on both Windows and WSL (WSL's through localhost forwarding).
  - **macOS:** `brew services start caddy`, a launchd agent running as the user from login (decided 2026-11-14; see [macOS](#macos)). It's chosen over running as root from boot, which would match Windows more closely, because it needs no root and removes the admin-API risk. `sudo brew services` is the fallback only if the [Mac checklist](#checklist-for-a-mac) shows the user service can't bind ports 80 and 443 on `127.0.0.1`.
- **Local names stay:** each project's sites file has its `.localhost` name (e.g. `myapp.localhost`) alongside its domain name. Local names work offline and with no tunnel running.
- **One sites file per project**, with that project's named sites. Throwaway servers can use a port wildcard (`<port>.port.localhost`, limited to an allowed list of ports) instead.

### Reaching dev servers from other devices

- **Two options in the guide, by how long the access is needed** (decided 2026-11-14):
  - **One-off sharing** (testing a webhook, letting someone take a look): a quick tunnel straight at the dev server, with no account, admin, Caddy or project change. See step 9 of [Set-up as tested](#windows).
  - **Regular access** (a stable name, behind a login): the named tunnel below, set up once per app.
- **Team default for regular access: Cloudflare Tunnel with Access**, for private access as well as public.
  - **One tunnel per person.** An admin creates each tunnel and gives that person only its token.
  - **Hostnames point at Caddy,** one route per app, so a project's routing lives in its sites file. The admin adds each route.
  - **Access** puts a login in front of each hostname, with a Bypass policy for paths that must stay open (e.g. webhooks).
  - **One Access application per person** (decided 2026-11-15, Still open 14): `<person>-*.<work domain>` covers all of that person's routes, so a new app needs only its route and is behind the login from the start. Each webhook path still has its own Bypass application, which takes precedence. This replaces an Access application per hostname.
- **Personal option: Tailscale.** A wildcard DNS record (*DNS only*) points at Windows' tailnet address (`meeg-laptop`), and Caddy holds a Let's Encrypt wildcard certificate for it, proven with a DNS challenge through Cloudflare's API. A tunnel is still used when something outside the tailnet must reach a server (webhooks, public access).
  - **How tailnet traffic reaches Caddy** (decided 2026-11-14, after the spike): Tailscale forwards it, with `tailscale serve --bg --tcp=443 tcp://127.0.0.1:443`. Caddy serves the tailnet names on loopback like every other site, and never binds the tailnet address.
  - **Why:** a Caddy site bound to the tailnet address stops the whole service from starting while Tailscale is down, `.localhost` names included (Still open 5).
  - **The forwarding is raw TCP,** so Caddy still holds the certificate. It sees requests as coming from `127.0.0.1`.
- **Tailscale runs on Windows only** (decided 2026-11-14). This replaces the earlier decision that WSL stays its own tailnet device with Tailscale SSH.
  - **How WSL is reached:** Windows forwards one tailnet port per WSL distro to that distro's existing SSH server, e.g. `tailscale serve --tcp=2222 tcp://127.0.0.1:2222` reaches the server the Windows Herdr app already uses on `127.0.0.1:2222`. Logins use keys, so the phone's key is added in WSL.
  - **Why:**
    - all WSL 2 distros share one network, so only one distro could be its own tailnet device;
    - Tailscale advises running it on the Windows host only;
    - the Herdr mobile app takes an address, user and port (checked by the user 2026-11-14).
  - **What it drops:** the exploration's `tailscale.ps1`, its module and tests. Nothing in WSL needs Tailscale.
  - **The Windows host** is still reached on port 22 through its OpenSSH server, limited to tailnet addresses.

### Names and domains

- **Domains:** a new domain, bought for this alone, for personal use; the spare domain already held at work for the team.
- **Cloudflare accounts** (2026-11-14):
  - **Personal:** the new domain can go in the existing personal account. Only the user manages it and all its domains are theirs, and the Caddy token can be limited to the one domain.
  - **Work:** the spare domain should be in a Cloudflare account of its own, so the people and tunnels set up for this can't reach other internal or client domains and resources. Account-wide pieces would otherwise be shared: tunnels, the Access organisation and its login domain, and anyone invited as an admin. To confirm with the team (Still open 13).
- **Each route has its natural shape:**
  - **Tunnel:** `<person>-<app>.<work domain>`, one level deep, because Cloudflare's free Universal SSL certificate covers only `*.<domain>`.
  - **Tailscale:** `<app>.<machine>.<personal domain>`, with one DNS wildcard and one certificate per machine.
  - **Personal tunnel names:** `<app>.<personal domain>`, e.g. `myapp.meeglocal.net` (decided 2026-11-14).
    - **Routing:** one wildcard route, `*.meeglocal.net` → the laptop's tunnel → Caddy, sits behind one wildcard Access app. A new app then needs only its sites-file entry, and webhook paths get their own Bypass apps.
    - **Telling them apart:** the extra machine label (`.laptop`) marks a name as tailnet-only.
    - **More machines:** a second machine can still get exact per-app routes, as an exact DNS record takes precedence over the wildcard.
    - **The wildcard route works** in the dashboard (Still open 6, tested 2026-11-15), so the fallback of one route per app isn't needed.
  - **One project's names, side by side:**

    ```
    public (tunnel + Access):   myapp.meeglocal.net
    tailnet only (Tailscale):   myapp.laptop.meeglocal.net
    local:                      myapp.localhost

    DNS:
      *.meeglocal.net         CNAME <tunnel>.cfargotunnel.com (proxied)
      *.laptop.meeglocal.net  A 100.x.y.z (DNS only)
    ```

### Windows service

- **Run Caddy as tested in the trial, and accept the risk.**
  - **What was tested:** the service runs as LocalSystem, with its admin API on, and the config is in `C:\ProgramData\Caddy\`.
  - **The risk:** any local process can reconfigure Caddy through its admin API, and ordinary users can probably add sites files.
  - **Why accept it:** it's security against convenience, and how likely either is to be exploited is unclear.
  - **Also document a hardened alternative:** `admin off` (changes apply by restarting the service; trust by importing `root.crt`), with the config under `C:\Program Files\Caddy\`. Tested since: see Still open 7.
- **`skip_install_trust`** goes in the top Caddyfile. Trusting is its own step in the guide, so the service's failed attempts at each start are just noise.
- **IIS:** for machines that also run IIS, the Windows docs get a short section on switching by hand: `iisreset /stop`, then `sc.exe start caddy`, and the reverse.
- **Old Caddy roots:** the docs get an optional clean-up step for people moving from per-project `caddy run`, removing the unused roots, the per-user winget Caddy and its `%APPDATA%\Caddy` folder.

### Dotfiles and docs

- **Only what a typical developer would do, and only what's officially documented** (carried over from the work trial):
  - **Docs to point at:** every command, config line and tool is one a typical developer would use, covered by official docs (Caddy, Microsoft, Cloudflare, Homebrew, Vite, Next), so the team can be pointed at those docs for every step.
  - **Examples:** `iisreset /stop` rather than `Stop-Service`; `caddy trust`, falling back to importing `root.crt` by double-clicking it.
  - **Admin steps:** the person runs them in their own `sudo` or "Run as administrator" terminal.
  - **No extras:** no permission changes on files or folders, and no NSS modules (Linux add-ons that change how names resolve).
- **Check every Cloudflare dashboard step against current docs before giving it,** as the dashboard changes often: context7 (`/cloudflare/cloudflare-docs`), the page's `index.md`, or Cloudflare's plugin where it's installed. This goes in the guide and in any brief for an agent.
- **Cloudflare's plugin is optional (2026-11-14).** This replaces the earlier decision that no Cloudflare tool is added.
  - **What it is:** `cloudflare@cloudflare`, enabled for this repo in `.claude/settings.json`. It includes Cloudflare's API server.
  - **What uses it:** nothing in the design, the docs or the guide depends on it. context7 or the docs pages are enough.
  - **Where it helps:** an agent can use it to look at an account, e.g. listing zones, DNS records, tunnels and Access apps.
  - **What it can't do:** its OAuth connection can't list or manage API tokens.
  - **The rule for agents:** they use it read-only. Any change in Cloudflare is made by the person, or by an agent only with that person's approval for that change, so "the person does everything in Cloudflare" still holds.
- **Windows and macOS steps are reference docs:**
  - which file: in `windows/README.md` or `tailscale/README.md`, or in new files where they fit better (e.g. `caddy/README.md`);
  - accurate and detailed enough to automate later, since Windows-side scripts are being added to this repo separately;
  - `cloudflared` is installed by documented steps too.
- **macOS is documented steps only.**
  - **Sources:** every step is researched and based on official docs or recorded facts.
  - **Kept close to Windows:** the steps stay as near to the Windows (+ WSL) steps as possible, diverging only where they must.
  - **After that:** someone runs through them on a Mac, with the [checklist](#checklist-for-a-mac), and they can be scripted from what actually happens.
- **Retire Caddy in WSL as part of this work:** `Install-Caddy` (apt repo, package, disabled service) and `Enable-UnprivilegedLowPorts` (`/etc/sysctl.d/50-unprivileged-ports.conf`). They get retire steps in `lib/Retire.psm1`, and `install.ps1`, `update.ps1` and `linux/README.md` are updated together.
  - This reverses the earlier decision to disable Caddy's service in WSL so that projects can run `caddy run` themselves.
  - Only the user runs these dotfiles at work, so nobody else is affected. The work projects move to the Windows service as the team adopts it.
- **DNS-filter steps are optional** (2026-11-14).
  - **Why:** NextDNS runs on the personal laptop and phone today, but may not on other machines, or for good.
  - **What the docs do:** every step that exists only because of a DNS filter is labelled *optional* and says when it applies:
    - allowlisting the domain (needed when the filter has rebinding protection);
    - `propagation_delay` and `propagation_timeout -1` in the `tls` block (needed when a filter app blocks direct DNS on port 53);
    - turning off "Use Tailscale DNS" on Android (needed when the phone has a Private DNS hostname set).
  - **Writing them:** each is described for any filter, with NextDNS as the example, and everything else works without them.
- **Tailscale script:** an expired login with other changed settings stays Tailscale's to report. `tailscale up` names the setting it wants; the README can mention it.

## What the work trial established

Tested on the work machine (Windows 11, WSL 2 with NAT networking) unless marked otherwise. Details and sources are under [Set-up as tested](#set-up-as-tested).

- **Caddy on Windows serves both sides,** with one certificate authority to trust (`caddy trust`). Under NAT, a Caddy in WSL can't reach Windows dev servers, and tools inside WSL can't reach a Caddy on Windows; they use the dev server's `localhost:<port>` instead.
- **Local names:** `.localhost` sites with Caddy's own certificate authority work in Chrome, with hot reload, for Vite and Next and no dev-server changes. Tools other than browsers need a hosts entry for each name.
- **`default_bind 127.0.0.1 [::1]`** keeps every site on loopback.
- **The port wildcard** (`*.port.localhost` → `127.0.0.1:{labels.2}`, limited to an allowed list) works.
- **Cloudflare Tunnel:**
  - it passes the public Host header through unchanged;
  - the dev server's host check needs the public name added (Vite's `server.allowedHosts`, Next's `allowedDevOrigins`);
  - pointing a tunnel at Caddy needs a plain-HTTP site for the public name on its own port, and `trusted_proxies` for loopback, so apps see `https` and the visitor's address;
  - Access with a Bypass path works, and its path match ignores case.
- **The Linux unit logs its environment** (`caddy run --environ`), so a secret must never go in a service's environment there.

## Set-up as tested

The steps from the work trial, as the source for the reference docs the implementation plan will write. Each is marked:
- **tested** (run in the trial);
- **observed** (seen there, not set up by the trial);
- **decided, not tested** (chosen in this design after the trial);
- **docs only**.

Versions: Caddy 2.11.9, Vite 8.3.8, Next 16.4.6, Chrome.

### Windows

1. **Install Caddy machine-wide** *(tested)*.
   - **Where it comes from:** the Windows zip and its checksums file from [Caddy's GitHub releases](https://github.com/caddyserver/caddy/releases) (linked from [Install](https://caddyserver.com/docs/install)).
   - **How:** in PowerShell run as administrator, check the zip's SHA-512, then expand it into a folder only administrators can write to. Use the latest release's version in the file names, and only expand the zip if the two hashes match ([Get-FileHash](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash), [Expand-Archive](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.archive/expand-archive)):

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
2. **Create the configuration** *(tested, except where marked)*.
   - **Files:** as administrator, create `C:\ProgramData\Caddy\sites`, then `C:\ProgramData\Caddy\Caddyfile`:

     ```
     {
     	# Bind sites to loopback only, so dev servers aren't exposed to the network
     	default_bind 127.0.0.1 [::1]
     	# Trusting the certificate authority is its own step (5)
     	skip_install_trust
     	# Trust X-Forwarded-* headers only from loopback, where cloudflared connects from,
     	# so apps behind Caddy see the public scheme (https) and the real client address
     	servers {
     		trusted_proxies static 127.0.0.1/32 ::1/128
     	}
     }

     import sites/*.caddy
     ```

   - **`skip_install_trust`** is *decided, not tested*. It stops the service's failed attempts, at every start, to install its root into a trust store ("failed to install root certificate") ([global options](https://caddyserver.com/docs/caddyfile/options)).
   - **`trusted_proxies`** was tested on its own and is needed because tunnels point at Caddy. Without it, Caddy replaces the headers `cloudflared` sends, so the app sees `X-Forwarded-Proto: http` and `X-Forwarded-For: 127.0.0.1` ([reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)).
   - **`default_bind`** keeps every site, and the HTTP-to-HTTPS redirect server, on loopback.
   - **`import sites/*.caddy`** reads every file in `sites`; an empty match isn't an error, and an imported file can't hold global options ([import](https://caddyserver.com/docs/caddyfile/directives/import)). Sites written straight into the top file work alongside imported ones.
   - **Notepad** adds `.txt` to a name without an extension: in the Save dialog, set *Save as type* to *All files*.
   - **"Caddyfile input is not formatted"** means tabs and spaces are mixed. It's harmless, and `caddy fmt --overwrite <file>` tidies the file.
3. **Create the service** *(tested)*.
   - **Commands:** in PowerShell 7 (`pwsh`) run as administrator ([Running Caddy](https://caddyserver.com/docs/running), "Windows service"; [sc create](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/sc-create)):

     ```powershell
     sc.exe create caddy start= demand binPath= '"C:\Program Files\Caddy\caddy.exe" run --config C:\ProgramData\Caddy\Caddyfile'
     sc.exe start caddy
     ```

   - **Other shells:** only `pwsh` was tested. Windows PowerShell 5.1 is expected to mangle the inner quotes. In Command Prompt the form would be `binPath= "\"C:\Program Files\Caddy\caddy.exe\" run --config C:\ProgramData\Caddy\Caddyfile"` (not tested).
   - **`--config`** is needed because a service starts in `C:\Windows\System32`.
   - **`start= demand`** starts it only when asked, so it doesn't compete with IIS at boot. Without IIS, `start= auto` starts it with Windows *(docs only)*.
   - **Data:** the service keeps its data, including its certificate authority's private key, in `C:\Windows\System32\config\systemprofile\AppData\Roaming\Caddy`.
   - **Starting and stopping** (`sc.exe start caddy`, `sc.exe stop caddy`) need administrator rights.
   - **Logs:** a Windows service's output goes nowhere. To see Caddy's log while setting up, add this to the global options block, and remove it afterwards (Caddy rejects it written on one line):

     ```
     	log {
     		output file C:/ProgramData/Caddy/caddy.log
     	}
     ```
4. **Add a project's sites** *(tested)*.
   - **One file per project** in `sites`, named `<project>.caddy`. It holds the project's local names and, if it has one, its public name, with upstreams on `127.0.0.1`:

     ```
     myapp.localhost {
     	reverse_proxy 127.0.0.1:3000
     }

     # The public name, reached through the person's tunnel (step 9)
     http://<person>-myapp.<work domain>:5399 {
     	reverse_proxy 127.0.0.1:3000
     }
     ```

   - **The public name is a plain-HTTP site on a port of its own,** so Caddy doesn't try to get a public certificate for it ([addresses](https://caddyserver.com/docs/caddyfile/concepts#addresses)), and the port isn't IIS's 80. One port can serve every public name, as Caddy routes by name. The trial tested one site on `5399`; the port is provisional.
   - **Reload** from an ordinary terminal, as Windows services can't be reloaded the usual way ([Running Caddy](https://caddyserver.com/docs/running)) and this goes through the admin API:

     ```powershell
     & 'C:\Program Files\Caddy\caddy.exe' reload --config C:\ProgramData\Caddy\Caddyfile
     ```

   - **A stopped dev server** behind a working site returns `502` until it's started again. A request with a Host no site matches gets an empty `200`.
5. **Trust Caddy's certificate authority** *(tested)*.
   - **Command:** with the service running, in a terminal run as administrator, `& 'C:\Program Files\Caddy\caddy.exe' trust` ([caddy trust](https://caddyserver.com/docs/command-line#caddy-trust)).
   - **What it does:** it fetches the root from the admin API and installs it into the **current user's** Trusted Root Certification Authorities, even when run as administrator, after a Windows security dialog. Chrome then accepted the certificates (Edge and Firefox weren't tried).
   - **Run it as the account you browse with:** elevating with a separate administrator account would put the root in that account's store. Whether it works without elevation wasn't tested.
   - **To remove it:** `certutil -user -delstore Root <thumbprint>` *(tested)* ([certutil](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil)), or `caddy untrust` while the service runs *(docs only)*. PowerShell's `Remove-Item Cert:\CurrentUser\Root\<thumbprint>` fails with "The operation is on user root store and UI is not allowed".
6. **Make `.localhost` names resolve for tools other than browsers** *(tested)*.
   - Browsers resolve any `*.localhost` name to the local machine themselves; Windows' own resolver doesn't.
   - As administrator, add each name to `C:\Windows\System32\drivers\etc\hosts`, e.g. `127.0.0.1 myapp.localhost`.
   - **Windows' own `curl.exe`** resolves `.localhost` names itself, but rejects Caddy's certificates (`CRYPT_E_NO_REVOCATION_CHECK`) unless given `--ssl-no-revoke` *(tested on the personal laptop, 2026-11-14)*.
7. **A name for any port** *(tested, optional)*.
   - **The site:** `sites\ports.caddy` lets `5173.port.localhost` reach `127.0.0.1:5173`, for ports on an allowed list only:

     ```
     *.port.localhost {
     	@allowed host 5173.port.localhost 8080.port.localhost
     	handle @allowed {
     		reverse_proxy 127.0.0.1:{labels.2}
     	}
     	handle {
     		respond 403
     	}
     }
     ```

   - **`{labels.2}`** is the third label counting from the right, starting at 0 ([caddyhttp package docs](https://pkg.go.dev/github.com/caddyserver/caddy/v2/modules/caddyhttp); [reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy), "Upstream addresses").
   - **Tested results:**
     - an allowed port with a server returns its page;
     - an allowed port with nothing on it returns `502`;
     - a port not on the list returns `403`;
     - Chrome accepts the wildcard certificate.
   - **The allowed list:** keep it to ports any `*.port.localhost` page may reach, and never include `2019` (the admin API).
8. **Dev servers** *(tested with Vite and Next)*.
   - **Behind Caddy on a `.localhost` name,** neither needs a change, and hot reload works. [Vite's `server.allowedHosts`](https://vite.dev/config/server-options#server-allowedhosts) allows names under `.localhost` by default, and [Next's `allowedDevOrigins`](https://nextjs.org/docs/app/api-reference/config/next-config-js/allowedDevOrigins) allows `localhost` and its subdomains.
   - **Bind dev servers to `127.0.0.1`** (Vite `--host 127.0.0.1`, Next `-H 127.0.0.1`). Sites point at `127.0.0.1`, which Vite's default `localhost` may not listen on, and it keeps them off the network.
   - **A public name has to be added to the host check:**
     - Vite answers `403 Blocked request. This host is not allowed` until the name is in `server.allowedHosts` (a new config file needs a restart);
     - Next serves the page but blocks hot reload until the name is in `allowedDevOrigins`.
9. **Run a tunnel** *(tested, except the install; the install, with winget, tested since on 2026-11-16)*. *Cloudflare's docs since (checked 2026-11-15; [dev-proxy/README.md](../../../dev-proxy/README.md#tunnels) follows them):* the run-parameters page no longer says `--token` or `TUNNEL_TOKEN` take precedence over `--token-file`; and the [quick tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/) page now documents `--allowed-mail`, the 200-request limit and the lack of Server-Sent Events.
   - **Install `cloudflared`** with the Windows installer from [Cloudflare's downloads page](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/) *(docs only)*.
   - **Keep the token in a file only you can read,** e.g. `%USERPROFILE%\.cloudflared\<tunnel>.token`. Paste it into Notepad and save it there; never paste it into a terminal or a chat.
   - **Run it** in an ordinary terminal, and stop it with Ctrl+C. `--token-file` keeps the token out of shell history and the process list; a `--token` option or `TUNNEL_TOKEN` variable would take precedence over it ([run parameters](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/cloudflared-parameters/run-parameters/)):

     ```powershell
     cloudflared tunnel run --token-file "$env:USERPROFILE\.cloudflared\<tunnel>.token"
     ```

   - **What arrives:** the local service receives the public Host header unchanged, `X-Forwarded-Proto: https`, and the request body.
   - **Error overlays:** a dev server shows error overlays and stack traces to whoever can load the page, so keep Access in front of anything but a webhook path.
   - **A quick tunnel for one-off sharing** *(decided, not tested; docs only)*.
     - **Command:** in an ordinary terminal, stopped with Ctrl+C:

       ```powershell
       cloudflared tunnel --url http://localhost:3000 --http-host-header localhost:3000
       ```

     - **What you get:** a random `https://<words>.trycloudflare.com` address, printed in the output. It needs no account, and a new name comes with every run ([quick tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/)).
     - **`--http-host-header`** sends the request in with the Host the dev server expects, so its host check passes with no project change ([origin parameters](https://developers.cloudflare.com/tunnel/reference/origin-parameters/#httphostheader)).
     - **Limits:**
       - at most 200 requests in flight;
       - no Server-Sent Events;
       - one origin per tunnel;
       - a `config.yml` in `%USERPROFILE%\.cloudflared` can stop quick tunnels from working (per [an article](https://flaviocopes.com/cloudflare-quick-tunnels/), not Cloudflare's docs).
     - **Risks:**
       - anyone with the URL can reach that port, so stop it when done, and use a webhook's signature checks;
       - the name changes on every run, so a webhook's registration needs updating each time;
       - there's no account behind it to trace who opened it.

       The same article mentions an `--allowed-mail` option requiring an email PIN, which Cloudflare's docs don't mention.
     - **Point it at the dev server, not Caddy:** a quick tunnel serves one origin, and Caddy would route by a Host the dev server never sees.
10. **IIS, if the machine has it** *(tested)*.
    - **Why:** IIS holds ports 80 and 443 on every address, so IIS and Caddy take turns.
    - **Commands,** as administrator:

      ```powershell
      # Caddy on
      iisreset /stop
      sc.exe start caddy
      # IIS back
      sc.exe stop caddy
      iisreset /start
      ```

    - **What `iisreset /stop` does:** it stops W3SVC and WAS and frees both ports, but leaves the HTTP service (HTTP.sys) running, so the Print Spooler, SSDP Discovery, WinRM and the other services that depend on it carry on.
    - **Start types aren't changed.** No current Microsoft page for `iisreset` was found; `iisreset /?` lists its options.
11. **Optional clean-up after moving from per-project `caddy run`** *(decided, not tested; facts from the trial)*.
    - **What becomes unused:** the old *Caddy Local Authority* roots in the Windows user's store and in the Linux store (`/usr/local/share/ca-certificates/Caddy_Local_Authority_-_*.crt`), the per-user winget Caddy, and its `%APPDATA%\Caddy` folder.
    - **Removing them on Linux:** `caddy untrust` left two dangling links in `/etc/ssl/certs`, which `sudo update-ca-certificates --fresh` removed *(tested)*.

### Windows + WSL differences

- **Dev servers in WSL** are reached through WSL's localhost forwarding (`localhostForwarding`, on by default in [`.wslconfig`](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)). Sites files point at `127.0.0.1:<port>` exactly as for a Windows dev server *(tested, including hot reload)*.
- **Don't also run Caddy in WSL:** its forwarding would compete for ports 80 and 443, and it forwards a WSL Caddy's admin API to Windows' `127.0.0.1:2019` *(observed)*.
- **Tools inside WSL can't reach the names** under NAT networking *(tested)*. Use the dev server's `localhost:<port>` from WSL.
- **Names in the Windows hosts file resolve in WSL** through WSL's DNS forwarding, but to `127.0.0.1`, which in WSL is WSL's own loopback *(observed)*. Other `.localhost` names resolve only in `curl`, which handles them itself.

### Admin's guide: Cloudflare Tunnel

As found in Cloudflare's dashboard on 2026-11-12 *(tested)*, matching [create a tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/) and [add routes](https://developers.cloudflare.com/cloudflare-one/networks/routes/add-routes/) as checked on 2026-11-14.

*Cloudflare's docs since (checked 2026-11-15; [dev-proxy/README.md](../../../dev-proxy/README.md#admins-guide-cloudflare-tunnel) follows them):* creating a tunnel has no connector type to choose; Access's button is **Add public hostname**, not *Public DNS*; Cloudflare recommends creating the Access application before the route; and *Refresh token* doesn't cut off a `cloudflared` that's already connected, whose connections the docs only delete through the API.

**Setting up a person:**

1. **Their tunnel:** Networking → Tunnels → create a tunnel with the *Cloudflared* connector, named for the person. Copy the token from the install command it shows; don't run the command.
2. **The token:** hand it over privately, as you would a password. It runs that tunnel and nothing else.
3. **Each app's hostname:**
   - **Where:** on the tunnel, the *Routes* tab → *Add route* → *Published application*.
   - **Hostname:** enter the subdomain (`<person>-<app>`) and choose the domain.
   - **Service URL:** the person's Caddy public-name port, with its scheme, e.g. `http://127.0.0.1:5399`.
   - **DNS:** Cloudflare creates the DNS record for the hostname.
   - **Multi-level names:** a subdomain more than one level deep needs an Advanced Certificate.
4. **Access in front:** *(since decided: one application per person on `<person>-*`, Still open 14; the trial used one per hostname, as below)*
   - **The app:** Zero Trust → Access controls → Applications → *Create new application* → *Self-hosted and private* → *Public DNS*. Add the hostname with no path and an *Allow* policy, e.g. the person's email with the one-time PIN login.
   - **An open webhook path:** add a second application for the same hostname with the path (e.g. `webhook`) and a *Bypass* policy for *Everyone* ([policies](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/), [application paths](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/app-paths/)).
   - **Tested:** every other path, including `POST /`, redirects to the login. The bypass covers everything under its path but not lookalikes (`/webhookx`). It **ignores case** (`/Webhook` was open too), and requests through it carry no Access token.
5. **Once per zone: turn on [Always Use HTTPS](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/always-use-https/).** Without it, a tunnel hostname requested over `http://` is served over plain HTTP.

**When someone leaves**, in this order:
1. Delete each of their routes, and check DNS → Records for a CNAME left pointing at `…cfargotunnel.com`.
2. Delete their Access applications (bypass ones first).
3. Delete the tunnel, which makes its token useless. To keep the tunnel but cut off the old token, use *Refresh token* on its Overview *(docs only)* ([tunnel permissions](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/remote-tunnel-permissions/)).

**Nobody else runs `cloudflared tunnel login`:** the `cert.pem` it creates controls every tunnel in the account.

### Moving a project onto the service

- **Its sites file:** the project's site blocks as they are, with upstreams on `127.0.0.1:<port>` instead of `localhost:<port>`. `header_up Host {upstream_hostport}` can stay.
- **Its global options go.** The common ones aren't needed:
  - **`http_port 80` and `https_port 443`** are Caddy's defaults.
  - **`local_certs`** would make every site on the machine use Caddy's own authority, which `.localhost` names already do.
  - **`auto_https disable_redirects`** in the shared top file would turn off redirects for every project. A plain-HTTP site is served over HTTP whatever that setting is *(docs only)*.
- **`file_server` alongside `reverse_proxy`** never runs, as `reverse_proxy` comes first in Caddy's [directive order](https://caddyserver.com/docs/caddyfile/directives#directive-order) and handles every request. Check what it was meant for before removing it.
- **Scripts that start the dev server and `caddy run` together** go; the project's script for the dev server alone starts it.
- **The project's docs** about its own Caddy point at the guide instead.
- **Two projects with the same upstream port** still can't run at the same time.

### Assessed on paper, not used

- **Moving HTTP.sys to another loopback address** (`netsh http add iplisten 127.0.0.2`) would let IIS and Caddy run together.
  - **Who it affects:** it applies to every HTTP.sys user, not just IIS, and would need every IIS user's hosts entries changed.
  - **Unknowns:** Microsoft's pages don't say whether it needs the HTTP service restarted (which stops the Print Spooler and others).
  - **Limits:** it can't move an IIS site on a `.localhost` name.
  - **Status:** worth a separate trial if switching by hand becomes a nuisance.
- **Caddy in front of IIS** would move every IIS site's bindings and break Windows authentication and apps that build URLs from what they see. It's the most work to set up and undo.
- **WSL's mirrored networking** ([WSL networking](https://learn.microsoft.com/en-us/windows/wsl/networking)) would let tools in WSL reach the Windows Caddy on `127.0.0.1`. In exchange, Windows and WSL share one set of ports, and Docker Desktop's behaviour in that mode is undocumented.
- **`tailscale serve` in front of Caddy** sends a Host that no site matches, so Caddy returns an empty `200`. The machine would need a site for its Tailscale name. The personal Tailscale route avoids this, as DNS points straight at Caddy.

### Not checked in the trial

- WSL restarting: whether the names are down until WSL starts, then come back by themselves.
- Real projects: scratch Vite and Next apps stood in for them.
- macOS.
- The service at boot (`start= auto`), or as `NT AUTHORITY\LocalService`.
- Whether Caddy can bind `127.0.0.1:443` while IIS holds `0.0.0.0:443`.
- Browsers other than Chrome, and `caddy trust` without elevation.
- Whether ordinary users can add files to `C:\ProgramData\Caddy\sites`: inferred from `C:\ProgramData`'s permissions.

## macOS

**Docs only: nothing here has been run on a Mac.** Researched 2026-11-14. The steps mirror [the Windows steps](#windows) one for one, and each difference says why it can't be avoided. Whoever first runs them on a Mac works through [the checklist](#checklist-for-a-mac) below, and they can be scripted from what actually happens.

`$(brew --prefix)` is `/opt/homebrew` on Apple silicon and `/usr/local` on Intel Macs.

### Steps

1. **Install Caddy with Homebrew:** `brew install caddy`.
   - **Differs from Windows,** which installs Caddy's official release by hand. Here, Homebrew's formula is what provides the service (step 3).
   - **Status:** Caddy lists Homebrew as a community-maintained install method ([Install](https://caddyserver.com/docs/install)). Its formula builds the same release with Caddy's own build tool, `xcaddy` ([formula](https://github.com/Homebrew/homebrew-core/blob/main/Formula/c/caddy.rb)).
   - **The official alternative:** a macOS build on [Caddy's GitHub releases](https://github.com/caddyserver/caddy/releases) (`caddy_<version>_mac_arm64.tar.gz` or `_mac_amd64`). That would mean writing a launchd service by hand, which Caddy's docs don't cover ([Running Caddy](https://caddyserver.com/docs/running)).
   - **Updates:** `brew upgrade caddy`.
2. **Create the configuration.**
   - **Files:** the same top Caddyfile as on Windows, at `$(brew --prefix)/etc/Caddyfile`, with a `sites` folder beside it, so `import sites/*.caddy` works unchanged. The formula's service always reads that path, so it can't be moved.
   - **No admin rights needed:** Homebrew's prefix belongs to the user, so creating and editing these files needs no `sudo`. On Windows, the same step needs an administrator.
3. **Start the service:** `brew services start caddy`.
   - **What it does:** it starts Caddy now and at every login, as a launchd agent running as the user ([brew services](https://docs.brew.sh/Manpage)), with `caddy run --config $(brew --prefix)/etc/Caddyfile`.
   - **Where things go:**
     - **data,** including the certificate authority's private key: `$(brew --prefix)/var/lib`, as the formula sets the service's `XDG_DATA_HOME` and `HOME` there;
     - **log:** `$(brew --prefix)/var/log/caddy.log`, so no logging block is needed, unlike on Windows.
   - **Starting and stopping:** `brew services stop caddy` and `brew services start caddy`, with no admin rights. Windows needs an administrator.
   - **Differs from Windows,** which runs Caddy as a system service from boot. Running it as the user is the closest equivalent that needs no root, and it removes the admin-API risk, since anything that can reach the API can only do what the user already can.
   - **Unverified: ports 80 and 443.** If macOS doesn't let a process running as the user bind them on `127.0.0.1` (checklist item 1), the fallback is `sudo brew services start caddy`. That runs Caddy as root from boot, like Windows, with the admin-API risk that comes with it. Homebrew warns: "Only use `sudo` if you trust the prefix owner and the service software."
4. **Add a project's sites:** the same files as on Windows, then reload from any terminal. It works as on Windows, through the admin API ([caddy reload](https://caddyserver.com/docs/command-line#caddy-reload)):

   ```bash
   caddy reload --config "$(brew --prefix)/etc/Caddyfile"
   ```

5. **Trust Caddy's certificate authority:** with the service running, `caddy trust`, or `sudo caddy trust` if it fails without.
   - **How:** as on Windows, it fetches the root from the admin API, so it doesn't matter where the service keeps its data ([caddy trust](https://caddyserver.com/docs/command-line#caddy-trust); the docs say it "may need" `sudo` on Unix systems).
   - **Where it goes:** Caddy's docs don't say which macOS store. It's expected to be the System keychain, with a password prompt (checklist item 3).
   - **To remove it:** `caddy untrust`.
6. **Make `.localhost` names resolve for tools other than browsers:** add each name to `/etc/hosts`, e.g. `127.0.0.1 myapp.localhost`, editing it with `sudo`. Whether macOS's own resolver handles `.localhost` without an entry isn't documented (checklist item 4), and Safari is reported to rely on it.
7. **A name for any port:** the same `sites/ports.caddy` as on Windows.
8. **Dev servers:** the same as on Windows: bind to `127.0.0.1`, and add any public name to the host check.
9. **Tunnels.**
   - **Install `cloudflared`:** `brew install cloudflared` ([Cloudflare's downloads page](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/)), updated with `brew upgrade`. On Windows it has to be updated by hand.
   - **Run it:** the same commands as on Windows, with the token file at `~/.cloudflared/<tunnel>.token`:

     ```bash
     cloudflared tunnel run --token-file ~/.cloudflared/<tunnel>.token
     cloudflared tunnel --url http://localhost:3000 --http-host-header localhost:3000
     ```

     The first runs the person's named tunnel; the second is a quick tunnel for one-off sharing.
   - **Unverified: who can read the token file.** A Windows user's profile is private to them. Whether other accounts on the same Mac can read `~/.cloudflared` depends on the home folder's default permissions, which this research didn't confirm. If they can, the design's "no permission changes" rule would leave the token readable by them (checklist item 6).
10. **IIS:** not applicable.
11. **Optional clean-up after moving from per-project `caddy run`.**
    - **What's left:** old *Caddy Local Authority* roots in the keychain. Remove them in Keychain Access, or with `caddy untrust --cert <old root.crt>` where the old file still exists.
    - **Where the old files are:** per-user `caddy run` keeps its data in `~/Library/Application Support/Caddy` ([conventions](https://caddyserver.com/docs/conventions#data-directory)).

### Checklist for a Mac

Run through the steps above, then report on each:

1. **Ports:** with `brew services start caddy` (not `sudo`), does Caddy bind `127.0.0.1:443` and `127.0.0.1:80` with `default_bind 127.0.0.1 [::1]`?
   - **Check:** `brew services list`, the log, and `lsof -nP -iTCP -sTCP:LISTEN | grep caddy`.
   - **Why it's open:** Apple engineers say macOS stopped requiring root for ports below 1024 in Mojave. Later forum replies say binding to one specific address still needs root ([Apple Developer Forums](https://developer.apple.com/forums/thread/674179)). If it fails, try the `sudo` fallback in step 3 and say what changed.
2. **Firewall prompt:** does macOS's application firewall prompt when the service starts?
3. **`caddy trust`:** which keychain does it use, does it need `sudo`, and do Safari, Chrome and Firefox then accept `https://myapp.localhost` without a warning?
4. **Names without a hosts entry:** does `curl https://myapp.localhost` work, and does Node's `dns.lookup` resolve the name? Does Safari need a hosts entry?
5. **Dev servers:** a Vite and a Next dev server behind Caddy. Do hot reload and the port wildcard work?
6. **The token file:** who can read `~/.cloudflared`? Check with `ls -la ~/.cloudflared`.
7. **Tunnels:** a quick tunnel and, if the admin sets one up, the person's named tunnel through Caddy.
8. **After a restart:** does Caddy come back at login (or at boot with the `sudo` fallback)?
9. **Undo:** `brew services stop caddy`, `caddy untrust`, `brew uninstall caddy cloudflared`. Remove the hosts entries and `$(brew --prefix)/etc/Caddyfile`, the `sites` folder and `$(brew --prefix)/var/lib/caddy`, then say whether anything was left behind.

## Names

- **The project:** "dev proxy" (settled 2026-11-14): the always-on Caddy every dev server sits behind, however it's reached. Files and folders for it use `dev-proxy`, except where the repo names a folder for its tool (e.g. `caddy/`).

Provisional:

- **Team tunnel names:** `<person>-<app>.<work domain>`, kept over `<app>-<person>` (2026-11-15), as `<person>-*` covers them in Access and keeps a person's DNS records together. Person names have no hyphens, so no person's wildcard (`chris-*`) also matches another's names (`chris-p-myapp`).
- **Personal tunnel names:** `<app>.<personal domain>`, e.g. `myapp.meeglocal.net`.
- **Tailscale names:** `<app>.<machine>.<personal domain>`, with `<machine>` e.g. `laptop` (`myapp.laptop.meeglocal.net`).
- **The public-name port in Caddy:** `5399`.

## Still open

1. **Personal tunnel names: decided 2026-11-14,** `<app>.<personal domain>` through a wildcard route (see Names and domains).
2. **Tailscale route, Caddy's Cloudflare plugin: `caddy add-package`** (tested 2026-11-14).
   - **How:** with the service stopped, in an administrator terminal: `& 'C:\Program Files\Caddy\caddy.exe' add-package github.com/caddy-dns/cloudflare`. It downloads a build of the same version with the plugin added from caddyserver.com, and keeps the old binary as `caddy.exe.tmp`. Here it gave `dns.providers.cloudflare v0.2.4` on Caddy 2.11.9.
   - **Updates:** `caddy upgrade`, which keeps the plugins, per Caddy's docs, though not tried.
   - **Status:** both commands are marked experimental in Caddy's docs. The install starts from the official zip, as in the guide.
3. **Tailscale route, the Cloudflare API token: a file in the service's data folder, read with `{file.…}`** (tested 2026-11-14).
   - **The token:** a user token limited to Zone → Zone → Read and Zone → DNS → Edit on the one zone, with an expiry date ([create token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)). The secret is shown once, so it's saved straight away.
   - **The file:** saved from Notepad run as administrator, at `C:\Windows\System32\config\systemprofile\AppData\Roaming\Caddy\cloudflare.token`. Only administrators and the service can read that folder; an ordinary account is even denied reading its permissions.
   - **The site:** `dns cloudflare {file.C:/Windows/System32/config/systemprofile/AppData/Roaming/Caddy/cloudflare.token}` in the site's `tls` block. Caddy read it, and the DNS challenge succeeded.
   - **Why not the environment:** this keeps the token out of the service's environment, which Windows keeps in the registry.
   - **What it doesn't protect against** (found in the final review, 2026-11-16): Caddy reads the file itself, so with the admin API on, or `sites` writable by ordinary users, any local process could add a site that returns the file's contents. The Tailscale guide recommends the hardened set-up (item 7) on a machine that holds the token.
   - **Optional, if a DNS filter blocks port 53:** a filter app that blocks direct DNS (here the NextDNS Windows app) stops Caddy's own check that the challenge record has spread: "dial tcp 1.0.0.1:53: … forbidden by its access permissions". `propagation_delay 30s` and `propagation_timeout -1` in the `tls` block leave the check to Let's Encrypt ([tls](https://caddyserver.com/docs/caddyfile/directives/tls)). The staging certificate and then the real one were issued with them.
4. **Tailscale route: DNS filters with rebinding protection do block it** (found 2026-11-14 on the personal laptop).
   - **What happened:** with NextDNS in use, every plain DNS lookup of `spike.laptop.meeglocal.net` returned `45.32.235.161` (a server at Vultr) instead of `100.66.231.9`. That included lookups sent straight to `1.1.1.1`, `8.8.8.8` and Cloudflare's own nameserver, so something on the network catches all DNS traffic. Ordinary names were unaffected.
   - **The record itself is fine:** Cloudflare's and Google's DNS-over-HTTPS returned the right address.
   - **The fixes** ([Tailscale: DNS rebinding](https://tailscale.com/docs/reference/faq/dns-rebinding)):
     - exempt the domain in the filter: NextDNS's Allowlist, per [NextDNS staff](https://help.nextdns.io/t/q6hl0vb/support-whitelist-for-dns-rebinding-protection);
     - Tailscale split DNS for the domain: Tailscale's docs only promise DNS-over-HTTPS for global nameservers, so plain lookups may still be caught;
     - turn the protection off;
     - override DNS servers in Tailscale.
   - **What fixed it here** *(optional step, only with a filter that has rebinding protection)*: adding `meeglocal.net` to the NextDNS profile's Allowlist. Afterwards every plain lookup, including the system resolver's, returned `100.66.231.9` *(tested)*.
   - **Android with a Private DNS hostname** (here NextDNS) lost all DNS once Tailscale connected, showing "Network has no internet access. Private DNS server cannot be accessed" and `ERR_NAME_NOT_RESOLVED` in Chrome. This is a known clash ([tailscale#4252](https://github.com/tailscale/tailscale/issues/4252)).
     - **What fixed it here** *(optional step, only with a Private DNS hostname set)*: turning off "Use Tailscale DNS" in the phone's Tailscale app (Settings → DNS settings). The phone then resolved `spike.laptop.meeglocal.net` through NextDNS (allowlisted) and loaded it over the tailnet, on Wi-Fi and on mobile data *(tested 2026-11-14)*.
     - **The cost:** Tailscale names such as `meeg-laptop` don't resolve on the phone, so the phone uses addresses, or names on the domain.
     - **Other fixes,** not tried: set Private DNS to Automatic; or make NextDNS the tailnet's DNS in Tailscale's admin console ([Tailscale: NextDNS](https://tailscale.com/kb/1218/nextdns)), which changes DNS for every tailnet device.
   - **The guide should say,** as an optional step: if a DNS filter with rebinding protection is in use, the Tailscale route needs the domain exempted from it, on every network and device that uses it. Without such a filter, nothing is needed.
   - **Tunnels aren't affected:** tunnel names point at Cloudflare's public addresses.
   - **The set-up on 2026-11-16** (the same laptop, the NextDNS app running): with the Allowlist entry, `*.laptop` names resolved to the tailnet address through `1.1.1.1` and through the system resolver. Direct DNS on port 53 also worked, and Caddy got the wildcard certificate without the propagation lines, so whatever blocked port 53 in the spike didn't recur. The guide keeps those lines as a step to take only when the log shows the error.
   - **Cloudflare's dashboard** shows a record pointing at a tailnet address as "DNS only - reserved IP", with no proxy choice, as it can't proxy reserved addresses.
5. **Tailscale route: Caddy can't bind the tailnet address when Tailscale is down; Tailscale forwards to it instead** (tested 2026-11-14 on the personal laptop).
   - **The failure:** with a site using `bind 100.66.231.9`, starting Caddy while Tailscale was disconnected failed with "listen tcp 100.66.231.9:443: bind: The requested address is not valid in its context". Caddy refused its whole config, so the service stopped and the `.localhost` sites went down too.
   - **The fix:** no `bind` on the tailnet site, which then sits on loopback through `default_bind`. Tailscale forwards with `tailscale serve --bg --tcp=443 tcp://127.0.0.1:443`, run as the user with no admin rights. This raw TCP forward passes the TLS connection through, so Caddy's Let's Encrypt certificate is what the phone sees.
   - **Tested:**
     - the phone loaded the site through it;
     - with Tailscale disconnected, Caddy kept serving its local sites;
     - Caddy restarted cleanly with Tailscale disconnected;
     - after reconnecting, `tailscale serve status` showed the forward back by itself, and the tailnet name loaded again.
   - **A full Windows restart** (*tested* 2026-11-16 on the personal laptop, hardened set-up, service `start= auto`): Caddy was running by the time of login and the 443 forward was back, so the tailnet name answered with nothing started by hand.
   - **Other ways round it,** not used: restarting the service on failure (`sc.exe failure`), which leaves every name down until Tailscale connects; and a dependency on the Tailscale service, which orders start-up but doesn't wait for the connection.
6. **Tunnel wildcard hostnames (checked 2026-11-14):**
   - **Shared work domain: ruled out.** A tunnel's ingress rules accept `*.example.com` but not a wildcard inside a hostname ([configuration file](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/configuration-file/)), so there's no wildcard per person under `<person>-<app>.<work domain>`.
   - **Personal domain: possible.** One person owns the whole domain, so `*.<personal domain>` → Caddy could cover every app.
   - **The dashboard accepts a wildcard published application** (*tested* 2026-11-15 on the personal domain, with a throwaway tunnel, since deleted). A route with subdomain `*` was added with no error, and DNS → Records then showed a proxied `*` record of type *Tunnel* pointing at the tunnel, not a CNAME. Every name tried under the domain reached the local service through it. Cloudflare's docs still show wildcard hostnames only in a locally-managed tunnel's config file.
   - **What's left for the personal tunnel:** nothing on this point; the one-route-per-app fallback isn't needed.
7. **The hardened alternative: tested 2026-11-14 on the personal laptop, and it works** (Caddy 2.11.9, official zip, service `start= demand`, Chrome).
   - **The config:** `admin off` in the global options, with the top Caddyfile, `sites` and the log under `C:\Program Files\Caddy\`. The service is created with `--config "C:\Program Files\Caddy\Caddyfile"`, quoted because of the space.
   - **What it showed:**
     - nothing listens on 2019, and the log says "admin endpoint disabled";
     - `caddy reload` fails with "connection refused";
     - a change applies after `sc.exe stop caddy; sc.exe start caddy` as administrator;
     - an ordinary user creating a file in `sites` gets "Access … is denied";
     - with `skip_install_trust`, the log says trust-store installation is disabled, with no failed attempts.
   - **Trusting it:** the root certificate is only readable by administrators (it sits in the service's data folder). So an administrator copies `…\systemprofile\AppData\Roaming\Caddy\pki\authorities\local\root.crt` out, and the user runs `certutil -user -addstore Root <file>` in an ordinary terminal, confirming the Windows dialog. Chrome then loaded the site with no warning.
   - **Windows' `curl.exe`** fails on Caddy's local certificates with `CRYPT_E_NO_REVOCATION_CHECK`, as it checks for revocation and Caddy's local authority can't answer that. `curl.exe --ssl-no-revoke` works. This applies to both set-ups, not just the hardened one. `curl` resolves `.localhost` names itself, with no hosts entry.
8. **Quick tunnels at work:** does the team allow them? They need no account and leave no trace of who opened them.
9. **People managing their own tunnel's routes: needs a test by the work account's admins** (*docs only*, checked 2026-11-15). **Decided 2026-11-15:** the admin's guide mentions it as unverified.
   - **The role:** Cloudflare can scope a member's role to one tunnel: Manage Account → Members → the member's policy → Scope "Specific resources" → resource type "Cloudflare Tunnel instances" ([granular permissions](https://developers.cloudflare.com/tunnel/guides/granular-permissions/), updated 2026-09-11; [role scopes](https://developers.cloudflare.com/fundamentals/manage-members/scope/); [roles](https://developers.cloudflare.com/fundamentals/manage-members/roles/#resource-scoped-roles), updated 2026-10-12). Resource-scoped roles are in beta. The docs describe the scope only as "manage a specific Cloudflare Tunnel instance": they don't name the role to bind, or say whether it covers adding and removing published application routes.
   - **DNS:** routing a tunnel to a public hostname needs the DNS role on top of the account-scoped tunnel role ([tunnel permissions](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/remote-tunnel-permissions/#account-scoped-roles), updated 2026-06-23, found 2026-11-15). The docs don't say whether the same holds with a tunnel-scoped role. DNS roles are scoped to a whole domain, so DNS edit would let the person change any record on the work domain, other people's included.
   - **Other people's names:** nothing in the docs stops a member routing a hostname with another person's `<person>-<app>` prefix.
   - **Access:** creating an Access application needs an account-level Access role; the resource-scoped Access role edits one existing application only. With one Access application per person (item 14), a new route is behind the login from the start, but the admin would still add each webhook's Bypass application.
10. **Skipping the project changes for a named tunnel: the override works** (*tested* 2026-11-15 on the personal laptop with a quick tunnel; the dashboard settings are *docs only*).
    - **The idea:** the tunnel route's Host header override sends each request in as the app's `.localhost` name. The project's local site in Caddy then answers it, with no public site in the sites file and no host-check change in the project.
    - **The settings** ([origin parameters](https://developers.cloudflare.com/tunnel/reference/origin-parameters/), updated 2026-09-11): a remotely-managed tunnel's published route sets them in the dashboard under "Additional application settings": "HTTP Host Header" (`httpHostHeader`), "Origin Server Name" (`originServerName`), "Disable TLS certificate verification" (`noTLSVerify`) and "CA Pool" (`caPool`, a file path). "Match SNI to host" (`matchSNItoHost`) sends the Host override as the TLS name, so "Origin Server Name" isn't needed with it. The route: Service `https://127.0.0.1:443`, Host header `<app>.localhost`, the TLS name `<app>.localhost`, and either verification off or a CA pool. A CA pool needs a copy of Caddy's root that `cloudflared` can read, as the original sits where only administrators can read it.
    - **How it was tested:** Chocolatey's Caddy 2.11.9 run as the user with `https://myapp.localhost:8443` → a dev server on `127.0.0.1:3000`, `trusted_proxies` as in the Caddyfile, and `cloudflared` 2026.10.7: `cloudflared tunnel --url https://127.0.0.1:8443 --http-host-header myapp.localhost --origin-server-name myapp.localhost --no-tls-verify`. Port 8443 rather than the service's 443 changes nothing tested here. Everything was stopped and removed afterwards.
    - **What it showed:**
      - the page loaded through the tunnel's URL; the app saw `Host: myapp.localhost`, `X-Forwarded-Host: <the public name>`, `X-Forwarded-Proto: https` and the visitor's address first in `X-Forwarded-For`;
      - `--origin-ca-pool` with a copy of Caddy's root, in place of `--no-tls-verify`, also worked;
      - without the TLS name override the request failed with `502` ("tls: internal error"), verification off or not, as Caddy has no certificate for `127.0.0.1`;
      - a Vite 7 dev server with no host-check change served the page and its hot reload through the tunnel, while a request carrying the public name as Host got `403`;
      - a link the app builds from Host came out as `https://myapp.localhost/…`, which a visitor can't open. Apps that build links or callbacks from `X-Forwarded-Host` get the public name.
    - **Not tested:** a named tunnel's route set in the dashboard, and `matchSNItoHost`, which has no quick-tunnel flag.
    - **Decided 2026-11-15:** the tunnel guides document it as an option for named tunnels, with the route settings and the warning about links built from Host. The plain-HTTP public site in the sites file stays the default, as sign-in callbacks and links built from Host break with the override.
11. **macOS, to check on a Mac:** the [checklist](#checklist-for-a-mac). Above all: whether Caddy running as the user can bind ports 80 and 443 on `127.0.0.1`, which decides between `brew services` and the `sudo` fallback.
12. **Tailscale on Windows reaches WSL over SSH: works** (tested 2026-11-14 on the personal laptop).
    - **The forward:** `tailscale serve --bg --tcp=2222 tcp://127.0.0.1:2222`, run as the user, forwards the tailnet's port 2222 to WSL's existing SSH server through WSL's localhost forwarding. The server answered (`OpenSSH_10.0p2 Debian`).
    - **The phone:** the Herdr mobile app connected with `100.66.231.9`, user `meeg`, port `2222`, and showed the WSL machine's terminals. It used the address, as the phone has "Use Tailscale DNS" off (item 4).
    - **The order in the Herdr app:**
      1. add the machine first; the app then shows its public key;
      2. add that key to `~/.ssh/authorized_keys` in WSL (e.g. `herdr-mobile`, beside the Windows app's key);
      3. choose **Connect again**.
    - **The forward survives Tailscale reconnecting,** as `443` did (item 5), **and a full Windows restart** (*tested* 2026-11-16). After the restart the phone reached WSL soon after login because Docker Desktop, starting with Windows and integrated with the default distro, started Debian; without something like it, the guide's "Keep WSL running" task is what brings WSL up. The Windows host's SSH server was back too, but the Herdr app needed herdr-core, which only runs once the Windows Herdr app is opened.
    - **Since the 2026-11-16 set-up:** once the phone's key is already in `authorized_keys`, the Herdr app connects straight away rather than showing its key first.
13. **The work domain's Cloudflare account, to confirm with the team:**
    - **Where it is now:** which account the spare domain is in.
    - **If it shares an account with other domains:** whether to move it to a dedicated account, and how. Cloudflare's process for moving a domain between accounts hasn't been checked.
    - **Who runs it:** who the new account's admins are.
14. **One Access application per person, with a wildcard in the name: works** (*tested* 2026-11-15 on the personal domain, with made-up person names `alpha` and `beta`; everything since deleted).
    - **What the docs say:** a wildcard can go at the beginning or end of an Access application's subdomain, e.g. `*test.example.com` covers `alphatest.example.com`, and it never covers more than one label ([application paths](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/app-paths/), updated 2026-04-17). The docs don't state, for public hostnames, which of two overlapping applications wins.
    - **The set-up:** a tunnel with one `*` route to a header-echo server, and two Access applications with *Allow* policies, one on subdomain `*-alpha` and one on `beta-*`. The dashboard accepted both.
    - **What it showed** (curl, redirects not followed):
      - `one-alpha`, `two-alpha`, `x-one-alpha` and `ONE-ALPHA` went to the login; `alpha` and `one-alphax` reached the server;
      - `beta-one` and `beta-two` went to the login; `beta` and `xbeta-one` reached the server;
      - so either form matches any text in place of the `*`, hyphens included, and nothing else.
    - **Webhooks:** a Bypass application on `one-alpha` with path `webhook` wins over the `*-alpha` application. `/webhook`, `/webhook/sub` and `/Webhook` were open to GET and POST; `/`, `/webhookx` and `two-alpha/webhook` still went to the login. (The first attempt failed because the application's policy had been saved as *Allow*; with *Bypass* it worked within seconds.)
    - **What it changes** for the work domain: one Access application per person, `<person>-*.<work domain>`, covers all of that person's apps, so a new app needs only its route, and a route is behind the login from the start. Today's names already fit it, so the `*-<person>` form isn't needed for this. Routes are still one per app, as a route can't take a wildcard inside a name (item 6), and each webhook still has its own Bypass application.
    - **A full `*` application** (the personal domain's, *tested* 2026-11-16 on the personal laptop's own tunnel, `laptop`, with its `*` route): `devtest.meeglocal.net` and a name with no site both went to the login; the bare domain has no record and didn't connect; after the PIN the page loaded, a refresh didn't ask again, and hot reload worked. A Bypass under it wasn't tried.
    - **Decided 2026-11-15:** keep `<person>-<app>`, with one Access application per person on `<person>-*` and no hyphens in person names (see Reaching dev servers, and Names). One application for the whole domain would do if everyone's policy were the same, which is for the work account's admins to decide.

## Next steps

See the [project plan](../plans/2026-11-14-dev-proxy-project.md).

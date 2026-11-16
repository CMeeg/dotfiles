# Dev proxy

The dev proxy is one always-on [Caddy](https://caddyserver.com/docs/) that every dev server sits behind, so each project's dev server has a name rather than a port number, on the machine itself and from other devices. Names reached from other devices are on a domain you control, and one-off dev servers can get a name with no set-up at all.

One project's names, side by side:

| Name | Reached from | Example |
|---|---|---|
| `<app>.localhost` | this machine only, even offline | `myapp.localhost` |
| `<person>-<app>.<work domain>` | anywhere, through that person's tunnel, behind a login | `person-myapp.example.com` |
| `<app>.<personal domain>` | anywhere, through the machine's tunnel, behind a login | `myapp.example.net` |
| `<app>.<machine>.<personal domain>` | your own devices, through Tailscale | `myapp.laptop.example.net` |

The local name needs only the Windows steps below. The tunnel names are covered in [Tunnels](#tunnels), and the Tailscale name, an optional extra for personal machines, in [tailscale/README.md](../tailscale/README.md).

Each step is labelled:

- *tested*: run on Windows 11 with Caddy 2.11.9, Vite 8.3.8, Next 16.4.6 and Chrome;
- *observed*: seen while testing, but not something the steps set up;
- *docs only*: follows the linked official docs, but hasn't been run here.

The files this guide copies are beside it: [Caddyfile](./Caddyfile) (the top file), [sites/ports.caddy](./sites/ports.caddy) (a name for any port) and [example.caddy](./example.caddy) (the template for a project's sites file).

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
2. **Create the configuration** *(tested)*.
   - **Files:** as administrator, create `C:\ProgramData\Caddy\sites`, then copy in the top [Caddyfile](./Caddyfile) and [sites/ports.caddy](./sites/ports.caddy) from this repo's clone ([New-Item](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-item), [Copy-Item](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/copy-item)):

     ```powershell
     New-Item -ItemType Directory C:\ProgramData\Caddy\sites
     Copy-Item <dotfiles>\dev-proxy\Caddyfile C:\ProgramData\Caddy\
     Copy-Item <dotfiles>\dev-proxy\sites\ports.caddy C:\ProgramData\Caddy\sites\
     ```

     `<dotfiles>` is the clone's folder, e.g. `$env:USERPROFILE\.dotfiles`. `ports.caddy` is optional (step 7).
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
   - **`start= demand`** starts it only when asked, so after a restart it waits for `sc.exe start caddy`. That keeps it from competing with IIS at boot ([If you also use IIS](#if-you-also-use-iis)). Without IIS, `start= auto` starts it with Windows *(docs only)*.
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
   - **Run it as the account you browse with:** elevating with a separate administrator account would put the root in that account's store. Whether it works without elevation wasn't tested.
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

Both use `cloudflared`. Install it with the 64-bit Windows MSI from Cloudflare's [downloads page](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/) *(docs only)*. It doesn't update itself on Windows, so install a newer MSI now and then.

The Cloudflare pages linked in this guide were checked on 2026-11-15.

### One-off sharing: a quick tunnel

*Docs only* ([Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)). `--http-host-header` was tested with a quick tunnel through Caddy.

- **Command,** in an ordinary terminal, stopped with Ctrl+C:

  ```powershell
  cloudflared tunnel --url http://127.0.0.1:3000 --http-host-header localhost:3000
  ```

- **What you get:** a random `https://<words>.trycloudflare.com` URL, printed in the output. It needs no account, it stops working when `cloudflared` stops, and a new one comes with every run.
- **`--http-host-header`** sends each request in with the Host the dev server expects, so its host check passes with no project change ([origin parameters](https://developers.cloudflare.com/tunnel/reference/origin-parameters/#httphostheader)). Links the app builds from the Host come out as `localhost:3000`, which a visitor can't open.
- **Point it at the dev server:** a quick tunnel has one `--url`, so going through Caddy adds nothing.
- **A login in front:** `--allowed-mail <email>` makes visitors enter their email address and a one-time PIN first. Repeat it, or give a comma-separated list, for several people; `'*@example.com'` allows a whole domain (quoted, so the shell leaves the `*` alone). It needs an interactive browser, so it doesn't suit webhooks.
- **Limits:** no uptime guarantee; up to 200 requests in flight, with more getting `429`; no Server-Sent Events.
- **Not in official docs:** a `config.yml` in `%USERPROFILE%\.cloudflared` can stop quick tunnels from working ([an article](https://flaviocopes.com/cloudflare-quick-tunnels/)).
- **Risks:**
  - without `--allowed-mail`, anyone with the URL can reach that port, so stop it when done, and use a webhook's signature checks;
  - the name changes on every run, so a webhook's registration needs updating each time;
  - there's no account behind it, so nothing records who opened it.
- **Whether to use them:** where several people use this set-up under one organisation, whether quick tunnels are allowed is that organisation's call, so check first.

### Regular access: a named tunnel

*Tested, except the install.* Each person runs their own tunnel, which an admin creates and hands them the token for ([Admin's guide](#admins-guide-cloudflare-tunnel)). Every route on it points at Caddy's public-name port, `5399`, and Caddy routes each name to its dev server.

1. **The token file:** keep the token in a file only you can read, e.g. `%USERPROFILE%\.cloudflared\<tunnel>.token`. Paste it into Notepad and save it there (*Save as type*: *All files*); never paste it into a terminal or a chat.
2. **Run it** in an ordinary terminal, and stop it with Ctrl+C. `--token-file` keeps the token out of shell history and the process list ([run parameters](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/run-parameters/#token-file)):

   ```powershell
   cloudflared tunnel run --token-file "$env:USERPROFILE\.cloudflared\<tunnel>.token"
   ```

3. **The project's public site:** for each app the admin routes to you, add its public name to the project's sites file as a plain-HTTP site on port `5399`, as in [example.caddy](./example.caddy), and reload (step 4):

   ```
   http://person-myapp.example.com:5399 {
   	reverse_proxy 127.0.0.1:3000
   }
   ```

4. **The dev server's host check:** add the public name to [Vite's `server.allowedHosts`](https://vite.dev/config/server-options#server-allowedhosts) or [Next's `allowedDevOrigins`](https://nextjs.org/docs/app/api-reference/config/next-config-js/allowedDevOrigins). Until then, Vite answers `403` and Next blocks hot reload (step 8).
5. **What arrives at the app:** the public Host unchanged, `X-Forwarded-Proto: https`, the visitor's address in `X-Forwarded-For`, and the request body. The top file's `trusted_proxies` is what keeps the forwarded headers: without it, Caddy replaces the ones `cloudflared` sends, and the app sees `http` and `127.0.0.1` (step 2).
6. **Error overlays:** a dev server shows error overlays and stack traces to whoever can load the page, so keep Access in front of everything but webhook paths.

To stop using a tunnel, see [Removing](#removing).

### Option: skip the project changes with a Host override

*Tested with a quick tunnel and Vite 7; the dashboard settings are docs only.* A route can send each request in as the app's `.localhost` name, so the project's local site answers it, with no public site in the sites file and no host-check change. The admin sets this per route, under the route's **Additional application settings** ([origin parameters](https://developers.cloudflare.com/tunnel/reference/origin-parameters/), [HTTPS origins](https://developers.cloudflare.com/tunnel/troubleshooting/https-origins/)):

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

On your own domain you're the admin, so the [Admin's guide](#admins-guide-cloudflare-tunnel) applies, with one tunnel per machine and one wildcard route in place of a route per app. A new app then needs only its sites-file entry. *Docs only, except where marked.*

- **Names:** `<app>.<personal domain>`, e.g. `myapp.example.net`, one level deep so Cloudflare's free certificate covers them.
- **The tunnel:** one per machine, named for it, run as in [Regular access](#regular-access-a-named-tunnel).
- **The wildcard route:** subdomain `*` on the domain → Service URL `http://127.0.0.1:5399`, behind one Access application with subdomain `*`. A `*.example.net` application covers `myapp.example.net`, but not the domain itself or deeper names ([application paths](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/app-paths/)). Webhook paths get their own Bypass applications, one per hostname.
- **A new app:** add `http://<app>.<personal domain>:5399` to the project's sites file, and the name to its host check. Nothing changes in Cloudflare.
- **The dashboard takes the wildcard route** *(tested with a throwaway tunnel)*, though Cloudflare's docs show wildcard hostnames only in a locally-managed tunnel's config file. DNS → Records then shows a proxied `*` record of type *Tunnel*, not a CNAME. Access applications with a partial wildcard (e.g. `*-alpha`) matched as the docs describe, and a Bypass application for one hostname's webhook path took precedence over them *(tested)*; a full `*` Access application wasn't tried.
- **A second machine:** give it exact routes per app on its own tunnel. An exact DNS record takes precedence over the wildcard ([wildcard DNS records](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/#specific-dns-records-take-precedence-over-wildcard-records)).
- **Tailscale names** (`<app>.<machine>.<personal domain>`) have their own DNS record: see [tailscale/README.md](../tailscale/README.md).

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
- **The per-user Caddy on Windows:** `winget uninstall --id CaddyServer.Caddy` if winget installed it ([winget uninstall](https://learn.microsoft.com/en-us/windows/package-manager/winget/uninstall)), then delete its data folder, `%APPDATA%\Caddy` ([conventions](https://caddyserver.com/docs/conventions#data-directory)).
- **Old roots in WSL:** WSL's Caddy put its roots in `/usr/local/share/ca-certificates/Caddy_Local_Authority_-_*.crt`. With Caddy gone from WSL, delete them and rebuild the trust store's links ([update-ca-certificates](https://manpages.debian.org/stable/ca-certificates/update-ca-certificates.8.en.html)):

  ```bash
  sudo rm /usr/local/share/ca-certificates/Caddy_Local_Authority_-_*.crt
  sudo update-ca-certificates --fresh
  ```

  `--fresh` also removes dangling links that `caddy untrust` leaves in `/etc/ssl/certs` *(tested)*.

## Optional: the hardened set-up

The set-up above runs Caddy as the trial did, and accepts a risk: any local process can reconfigure Caddy through its admin API on `127.0.0.1:2019`, and ordinary users can probably add sites files, as `C:\ProgramData` lets them create files. Whether either is likely to be exploited is unclear. The hardened set-up turns the admin API off and keeps the config where only administrators can write *(tested)*. The cost: every change needs an administrator to restart the service, and trusting the root is done by hand.

1. **The config,** under `C:\Program Files\Caddy\` beside `caddy.exe`: the top `Caddyfile`, with `admin off` added to its global options block ([admin](https://caddyserver.com/docs/caddyfile/options#admin)), and the `sites` folder. For a log, use `output file "C:/Program Files/Caddy/caddy.log"`, quoted because of the space.
2. **The service,** as administrator. If the default service already exists, remove it first with `sc.exe stop caddy; sc.exe delete caddy` ([sc delete](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/sc-delete)). The config path is quoted because of the space:

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

What the test showed: nothing listens on 2019 and the log says "admin endpoint disabled"; an ordinary user creating a file in `sites` gets "Access … is denied"; and Chrome loads the sites with no warning.

## Optional: DNS filters

Some steps in these guides exist only because of a DNS filter, such as NextDNS. Each is labelled *optional* and says when it applies; without a filter, none of them is needed.

- **The Windows dev proxy on its own:** nothing applies. `.localhost` names never leave the machine.

## Removing

As administrator, unless marked *(docs only, except where marked)*:

1. **The service:** `sc.exe stop caddy; sc.exe delete caddy` ([sc delete](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/sc-delete)).
2. **Caddy and its config:** delete `C:\Program Files\Caddy`, and `C:\ProgramData\Caddy` unless you used the hardened set-up.
3. **The service's data:** delete `C:\Windows\System32\config\systemprofile\AppData\Roaming\Caddy`, which holds the certificate authority's private key.
4. **Hosts entries:** remove the names added to `C:\Windows\System32\drivers\etc\hosts` in step 6.
5. **The root,** in an ordinary terminal: `certutil -user -store Root` lists your roots; find *Caddy Local Authority* in a `Subject` line, then run `certutil -user -delstore Root <thumbprint>` with its `Cert Hash(sha1)` value *(tested)*, confirming the Windows dialog ([certutil](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil)). `caddy untrust` does the same, but only while the service still runs, so before step 1 *(docs only)* ([caddy untrust](https://caddyserver.com/docs/command-line#caddy-untrust)). PowerShell's `Remove-Item Cert:\CurrentUser\Root\<thumbprint>` fails with "The operation is on user root store and UI is not allowed".
6. **A tunnel,** in an ordinary terminal *(docs only)*:
   - stop `cloudflared` with Ctrl+C;
   - delete the token file, `%USERPROFILE%\.cloudflared\<tunnel>.token`, and `caddy-root.crt` beside it if you made one for the Host override;
   - remove the public sites from the projects' sites files, and the public names from their host checks;
   - uninstall `cloudflared` in Settings → Apps → Installed apps, if it's no longer wanted ([uninstall apps](https://support.microsoft.com/en-us/windows/uninstall-or-remove-apps-and-programs-in-windows-4b55f974-2cc6-2d2b-d092-5905080eaf98));
   - the admin deletes the tunnel, its routes and its Access applications ([When someone leaves](#admins-guide-cloudflare-tunnel)).

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
6. **Tunnels:** see [Tunnels](#tunnels).

---
name: adding-a-project
description: Use when a project's dev server needs a name through the machine's dev proxy (a `.localhost` name, a public name on a Cloudflare tunnel, or a Tailscale name), when moving a project off its own `caddy run` or Caddyfile, or when a dev proxy name fails, e.g. an empty 200, 502, 403 "Blocked request", CRYPT_E_NO_REVOCATION_CHECK, ERR_ADDRESS_UNREACHABLE, `caddy reload` refused, or the Caddy service not starting.
---

# Adding a project to the dev proxy

The dev proxy is one always-on Caddy that every dev server sits behind. How it's set up is in the dotfiles repo (usually `~/.dotfiles`): `dev-proxy/README.md`, and `tailscale/README.md` for tailnet names. This skill says what a project needs from it, and what each failure means; the guide has the detail.

**REQUIRED SUB-SKILL:** use workflow:changing-a-live-system for the machine's side: who does what, and a change list with an undo.

## First, find out

- **The set-up:** hardened if `C:\Program Files\Caddy\Caddyfile` has `admin off` (sites in `C:\Program Files\Caddy\sites`, applied by restarting the service as administrator); otherwise the default (sites in `C:\ProgramData\Caddy\sites`, applied with a reload). On a Mac, the guide's macOS section.
- **The reload, always with the service's config:** `& 'C:\Program Files\Caddy\caddy.exe' reload --config C:\ProgramData\Caddy\Caddyfile`. Without `--config`, Caddy loads the Caddyfile in the current folder, and a project's own Caddyfile would replace every site the service serves.
- **Which names,** asking which domain "my tunnel" is on if it isn't clear: local only; a public name (personal domain: `<app>.<personal domain>`, nothing to change in Cloudflare on the machine with the `*` route, while a second machine needs a route per app and names the first doesn't use, as the guide's **Setting up a machine** table says; work domain: `<person>-<app>.<work domain>`, routed by the work account's admin); a tailnet name (`<app>.<machine>.<personal domain>`).
- **The dev server:** its framework, its port, and whether another project already uses that port.

## What a project needs

| Piece | Where | Who |
|---|---|---|
| A sites file, `<project>.caddy`, from the guide's `example.caddy`: the local name, and the public name as `http://<name>:5399` | the sites folder | default set-up: you, once the change list is approved, if you can write there (otherwise the person, as administrator), then the reload above (no admin rights needed); hardened: the person, as administrator, then a restart |
| Optional: a hosts entry, `127.0.0.1 <app>.localhost`, for tools other than browsers (browsers and Windows' `curl.exe` don't need it) | `C:\Windows\System32\drivers\etc\hosts` | the person, as administrator |
| A `handle` for the tailnet name | `tailnet.caddy` in the sites folder | the person, as administrator, then a restart |
| The dev server bound to `127.0.0.1`, on the sites file's port | the project's scripts | you |
| Each public and tailnet name in the host check: Vite's `server.allowedHosts`, Next's `allowedDevOrigins` | the project's config | you |

**Moving a project off its own Caddy:** the guide's **Moving a project onto the service**. Its Caddyfile and the scripts that run `caddy run` go: the project's own Caddy competes with the service for ports 80 and 443, and if it can't start, a wrapper such as `concurrently` can hide that; the per-user Caddy and its old roots are the guide's separate clean-up, which stops any other project still using them.

## Checks

- **Local:** the page loads in a browser with no certificate warning, and an edit shows through hot reload; this is the check that counts. `curl.exe --ssl-no-revoke -s -o NUL -w "%{http_code} %{size_download}" https://<app>.localhost` prints `200` and a size above `0`: a name with no site gets an empty `200` too.
- **Public:** the same `curl` (without `--ssl-no-revoke`) on the public name prints `302` (the Access login). A name with no site behind it gets `302` too, so the check that counts is after the login: the page loads and hot reload works.
- **Tailnet:** another device with Tailscale connected loads it.

## Symptoms

Where the fix belongs to another project, say so, and ask before changing it.

| Symptom | Meaning | Fix |
|---|---|---|
| An empty page with `200` | No site matches the name: the service answered, not the project | The sites file's name, or the change not applied (reload, or restart with the hardened set-up); a project still running its own Caddy isn't answering, as below |
| A project's own `caddy run` fails, or its names behave oddly | It competes with the service for ports 80 and 443 | Move the project onto the service |
| `502` | The site matches, but nothing answers on its upstream | Start the dev server on `127.0.0.1` and the sites file's port |
| `403 Blocked request. This host is not allowed` | Vite's host check | Add the name to `server.allowedHosts` (a new config file needs a dev server restart) |
| An empty `403` on `<port>.port.localhost` | The port isn't on `ports.caddy`'s allowed list | Use the project's own name, or add the port to the list |
| Next loads on the public name, but hot reload doesn't work | Next's host check | Add the name to `allowedDevOrigins` |
| `curl.exe`: `CRYPT_E_NO_REVOCATION_CHECK` | Windows' `curl` checks revocation, which Caddy's local authority can't answer | `curl.exe --ssl-no-revoke`; nothing is broken |
| `302` to `…cloudflareaccess.com` | The Access login, as intended | Log in |
| `404` on a tailnet name | `tailnet.caddy` has no `handle` for it | Add one (as administrator, then a restart) |
| `ERR_ADDRESS_UNREACHABLE` on a tailnet name | The device isn't on Tailscale, or the 443 forward has gone | Connect Tailscale; `tailscale serve status` on the machine |
| `ERR_NAME_NOT_RESOLVED` on a tailnet name | A DNS filter's rebinding protection, or Android's Private DNS | The Tailscale guide's **Optional: DNS filters** |
| `caddy reload`: connection refused | The hardened set-up (no admin API), or the service is stopped | Restart the service as administrator; `sc.exe query caddy` |
| The service won't start | One broken site stops them all: a site file error, the Cloudflare plugin missing after a zip update, a `bind` to the tailnet address, or ports 80 or 443 taken | The guide's logging block, then the log; `& 'C:\Program Files\Caddy\caddy.exe' list-modules` for the plugin |

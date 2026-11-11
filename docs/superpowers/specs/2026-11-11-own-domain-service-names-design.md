# Service names on your own domain (draft)

**Status:** exploring. The direction is agreed; nothing is built yet. The name of this design and every name marked *provisional* below may still change.

**Date:** 2026-11-11

## Where things stand

### 1. Tailscale (built, not committed)

The opt-in Tailscale setup is written and reviewed, and sits uncommitted in the working tree:

- `tailscale.ps1`, `lib/Tailscale.psm1`, `tests/Tailscale.Tests.ps1`, `tailscale/README.md`, plus links from `AGENTS.md`, `README.md`, `linux/README.md` and `windows/README.md`.
- Windows and WSL join the tailnet as two devices: WSL (`meeg-laptop-wsl`) uses Tailscale SSH, set up by the script; Windows (`meeg-laptop`) uses its OpenSSH server limited to tailnet addresses, set up by hand from the README.
- A fresh-eyes review found one bug (re-running without `-Hostname` after `tailscale down` or an expired login did nothing but reported success) and several smaller issues. All are fixed; the full Pester suite passes in WSL (159 tests).
- Not yet done: commit it, run it for real on this laptop, do the admin console and Windows steps, and connect the phone.

### 2. Own-domain service names (this design)

Agreed in discussion, not started. The rest of this document covers it.

## Goal

Open any service or dev server on these machines, from the phone or another computer, at a name like `https://myapp.wsl.example.com`:

- one name per service, never a port number;
- names on a domain you control, so they don't depend on the tailnet's name or Tailscale's device names;
- one-off dev servers get a name without any DNS or config change.

Out of scope: herdr and SSH. They keep using MagicDNS short names (`meeg-laptop-wsl`), which are already easy.

## Decisions so far

- **Why not `tailscale serve` alone:** it gives each device one name, so a second service needs a port (`--https=8443`) or a path (`--set-path=/api`), and paths break apps that expect to be served from `/`. Tailscale Services give per-service names but need a tagged device, which takes it out of your personal devices. Both stay documented in `tailscale/README.md` as they are.
- **DNS:** one wildcard record per machine at Cloudflare, *DNS only* (not proxied), pointing at that machine's tailnet address, e.g. `*.wsl.example.com` → WSL's `100.x.y.z`. Only tailnet devices can connect, and new services never need a DNS change.
- **Certificate:** one Let's Encrypt wildcard certificate per machine (`*.wsl.example.com`), proven with a DNS challenge through Cloudflare's API, so it works although the machine isn't reachable from the internet.
- **Front door:** Caddy runs as an always-on service, listening on the machine's tailnet address only. It holds the wildcard certificate and forwards every request, keeping the name that was asked for, to portless.
- **One-off servers:** [portless](https://github.com/vercel-labs/portless) starts each dev server on a free port and routes a name to it (`portless myapp pnpm dev`). It stays on its default of listening on `127.0.0.1` only, and serves the domain alongside `.localhost` (`--tld localhost,wsl.example.com`). Caddy and portless both use port 443, on different addresses, so they don't clash.
- **Chosen over portless on its own:** portless can serve the wildcard certificate itself in LAN mode, but LAN mode listens on every network (so also on café Wi-Fi unless firewalled), and the certificate would need a separate renewal tool. Caddy renews its own certificates and limits listening to the tailnet.
- **Not used:** portless's `--tailscale` option gives each app a port on the device's Tailscale name (`https://devbox.ts.net:8443`), which is the port problem again.

### Proposed change to an earlier decision

Today `install.ps1` (`Install-Caddy`) disables Caddy's systemd service, and `Enable-UnprivilegedLowPorts` lets ordinary processes bind ports 80 and up, so that projects can run `caddy run` on 80/443 themselves (documented in `linux/README.md` → Caddy). This design runs Caddy as a service again, so per-project `caddy run` would be replaced by portless.

This isn't decided yet: no project on this laptop uses `caddy run`, but projects on the work machine do. The work-machine trial (below) decides it. When it's decided, update `install.ps1`, `update.ps1`, `linux/README.md` and this document together, and add a retire step if anything is removed. The `sysctl` may be worth keeping: portless's `--unprivileged` mode needs it to bind 443 without `sudo` on Linux.

## How it fits together

```
phone / other computer (on the tailnet)
  │  https://myapp.wsl.example.com
  │  DNS (Cloudflare, DNS only): *.wsl.example.com → WSL's tailnet address
  ▼
Caddy service on WSL, listening on <tailnet address>:443
  │  wildcard certificate for *.wsl.example.com (Let's Encrypt, Cloudflare DNS challenge)
  │  forwards with the original name
  ▼
portless proxy on 127.0.0.1:443
  │  routes myapp.wsl.example.com (and myapp.localhost) by name
  ▼
dev server on a port portless picked (4000–4999)
```

## Provisional names

- **This design:** "service names on your own domain".
- **Machine label:** `wsl` in `*.wsl.example.com`. Every machine needs its own label (the work machine too).
- **Domain:** `example.com` is a placeholder (see Open questions).

## Open questions

- Which domain to use, and whether it's already on Cloudflare. A spare domain keeps the risk of a leaked API token small: Cloudflare tokens can be limited to one zone (domain) but not to a subdomain.
- Machine labels for each machine.
- Whether Windows-hosted servers need the same setup (proposed: WSL only at first).
- How Caddy gets the Cloudflare plugin: it isn't in the apt package, so Caddy would come from Caddy's download service or a custom build, and `install.ps1`/`update.ps1` would install and update it.
- Where the Cloudflare API token lives (proposed: `~/.secrets`, limited to editing DNS on one zone) and how the Caddy service reads it.

## Not verified yet

Check each of these in the spike before writing a plan:

- that portless routes a request forwarded by Caddy for `myapp.wsl.example.com` (as opposed to `myapp.localhost`), and how one app answers on several TLDs;
- how Caddy forwards to portless's HTTPS, e.g. trusting portless's local certificate authority (`~/.portless/ca.pem`) and sending the requested name;
- that Caddy can listen on the tailnet address at boot, before or after `tailscaled` has brought it up;
- that phones' and routers' DNS resolve a public name that points at a tailnet (`100.64.0.0/10`) address. Some routers and DNS filters with rebind protection refuse it; this is from memory;
- the Caddy Cloudflare plugin and download details.

Verified from portless's docs (2026-11-11; portless is pre-1.0 and needs Node 24 or later): `--tld` accepts multi-segment domains such as `dev.example.com` and can be repeated; `--cert`/`--key` take your own certificate; the proxy listens on `127.0.0.1` and `::1` unless LAN mode is on; `portless alias` routes a name to a fixed port; `portless compose up` routes Docker Compose services.

## Next steps

1. **Work-machine trial:** replace per-project `caddy run` with portless, locally only. The brief to hand to an agent there is [2026-11-11-portless-trial-brief.md](./2026-11-11-portless-trial-brief.md). Its report decides the Caddy question above.
2. **Spike on this laptop:** portless with `--tld`, Caddy in front on the tailnet address, and a Let's Encrypt staging certificate, opened from the phone. Answer "Not verified yet".
3. **Plan:** turn the results into an implementation plan: install and update steps, any retire steps, README, secrets, tests.

## Raised and not yet decided

- Commit the Tailscale work (part 1) before starting this.
- Windows-hosted dev servers (see Open questions).
- Tailscale script: if a login expires and another Tailscale setting was also changed since, `tailscale up` refuses and names the setting it wants. Left to Tailscale to report, since working around it would mean resetting your other settings.

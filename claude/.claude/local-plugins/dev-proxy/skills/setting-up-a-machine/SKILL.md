---
name: setting-up-a-machine
description: Use when setting up, moving, rebuilding or checking the dev proxy (Caddy as a Windows service, or on macOS), its Cloudflare tunnels or its Tailscale names on a machine, such as a new work laptop or a second personal machine, or when clearing out an old per-project or WSL Caddy.
---

# Setting up a machine for the dev proxy

**REQUIRED SUB-SKILL:** use workflow:changing-a-live-system for how to work with the machine's owner: taking stock, who does what, change lists with an undo, recording, secrets. This skill adds what's particular to the dev proxy.

## First

1. In the dotfiles repo (usually `~/.dotfiles`), read `dev-proxy/README.md` from **Setting up a machine**, then the sections it links for the parts that apply, including `tailscale/README.md` for Tailscale.
2. Take stock with its **Before you start** checklist.
3. Bring the choices from that section, each with a recommendation. Without a real project to test with, use a scratch Vite app on `127.0.0.1:5173`.

## Particular to the dev proxy

- **Plan the steps by the guide's order,** one change list per step of it.
- **Cloudflare dashboard steps:** check each against current docs before giving it (context7 `/cloudflare/cloudflare-docs`, the page's `index.md`, or Cloudflare's plugin, read-only).
- **Can't be undone here:** deleting a tunnel; the Let's Encrypt certificate for the tailnet names, which enters public logs; and refreshing a tunnel's token or deleting an API token, which cuts off whatever still uses the old one. Say so before the step that causes it, and prepare a script or command for it only when the person asks.
- **The person's own account:** trusting the root (`certutil -user`), the token file and the tunnel live under the account they browse with. On a work machine the elevated terminal may be a separate admin account, with its own `%USERPROFILE%`.
- **Tokens:** there are two, each from the dashboard into Notepad and straight into its file, as the guides say:
  - **the tunnel's token,** in `%USERPROFILE%\.cloudflared\<tunnel>.token`. One pasted into the chat is replaced: the tunnel's **Refresh token**, then the new token from **Add a replica**, as the guide's Admin's guide says (on a work tunnel, by its admins);
  - **the Cloudflare API token for Tailscale names,** in `cloudflare.token` in the Caddy service's data folder, which only administrators can read, so it's checked by the certificate being obtained.
- **The guide is the record of how to set up a machine** (the machine's own changes go in its change list): where reality differs, fix its step, and relabel a *docs only* step that now worked as *tested*. No personal values in `dev-proxy/` or `tailscale/`: use `<user>`, `<host>`, `<machine>`, `<person>`, `<work domain>`, `<personal domain>`. Ask before writing a work domain or tunnel name anywhere in the repo.
- **Moving a project off its own Caddy** changes that project: raise it as more scope (the dev-proxy:adding-a-project skill covers it).

## Machine types

The guide's table says which parts apply. On a **work machine**, the tunnel's token, routes, Access applications and zone settings (e.g. Always Use HTTPS) belong to the work account's admins. If the person is one of them, they make the change themselves, as the guide's Admin's guide says; otherwise it's a request to an admin, not something to do with whatever access the person has. Check with the person that the employer allows a root certificate, a system service and `cloudflared` on a managed machine.

## Finishing

Check each part as the guide says, pages in a real browser, then restart and check again.

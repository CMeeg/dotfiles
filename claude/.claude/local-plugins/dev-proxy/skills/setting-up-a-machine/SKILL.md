---
name: setting-up-a-machine
description: Use when setting up, moving, rebuilding or checking the dev proxy (Caddy as a Windows service, or on macOS), its Cloudflare tunnels or its Tailscale names on a machine, such as a new work laptop or a second personal machine, or when clearing out an old per-project or WSL Caddy.
---

# Setting up a machine for the dev proxy

The steps live in the dotfiles repo's guides, and this skill is how to carry them out on a real machine with the person who owns it. Their changes reach services, certificates, firewalls and Cloudflare and Tailscale accounts, so the person stays in charge of every change.

## First

1. In the dotfiles repo (usually `~/.dotfiles`), read `dev-proxy/README.md` from **Setting up a machine**, then the sections it links for the parts that apply, including `tailscale/README.md` for Tailscale.
2. Take stock with its **Before you start** checklist, read-only. Ask the person about what only they can see: dashboards, old tunnels and tokens, a DNS filter on their phone.
3. Bring the choices from that section, each with a recommendation, and record the answers. Without a real project to test with, use a scratch Vite app on `127.0.0.1:5173`.

## Who does what

- **The person, always:** every command that needs administrator rights or `sudo`, including installs that raise a UAC prompt (winget's), and every change in Cloudflare's, Tailscale's and a DNS filter's dashboards and on their phone. This holds even when they offer to hand it over ("your terminal is elevated, just do it"): say that these steps are theirs, and offer to prepare them.
- **You** run read-only checks, and commands without admin rights that the approved change list names. For anything of theirs, give one instruction, wait for "done", then check the result.
- **Scripts and commands you prepare** for them (asked for, or offered): a script in your scratch folder, checked to parse, or the exact CLI or API command. Before handing one over, explain what it does, step by step, and its risks. Never prepare one for a step that can't be undone (deleting a tunnel, a certificate entering public logs, anything else the guide says can't be undone): point them at the guide's step, and say it can't be undone.
- **Their own account:** what belongs to it runs as the account they browse with: trusting the root (`certutil -user`), the token file and the tunnel, which live under their `%USERPROFILE%`. On a work machine the elevated terminal may be a separate admin account, with its own profile.

## Before each step

For each step of the guide's order, show the exact changes, each with its undo, and wait for approval. Before giving any Cloudflare dashboard step, check it against current docs (context7 `/cloudflare/cloudflare-docs`, the page's `index.md`, or Cloudflare's plugin, read-only).

## Secrets

- Never ask for, accept, print or write down a token or key, and never open a file that holds one: check that it exists and its size only. One in an admin-only folder (`cloudflare.token`) is checked by the person, elevated, or by its result (the certificate obtained).
- Tokens go from the dashboard into Notepad and straight into their file, as the guides say.
- **A token pasted into the chat is exposed:** don't use it. Have it replaced (the tunnel's **Refresh token**, or the work account's admin for a work tunnel; a new API token), and the new one saved through Notepad.

## Recording

- Keep a list of every change with its undo, as it happens: in the plan, if one is being followed, otherwise ask where, suggesting a plan for the machine in the repo's `docs/superpowers/plans/`, shaped like the existing machine set-up plan there. Include dates that matter later, such as an API token's expiry, and requests still waiting on someone else, such as a work admin.
- Where reality differs from the guide, fix the guide's step: rewrite one that failed, and relabel a *docs only* step that now worked as *tested*. No personal values in `dev-proxy/` or `tailscale/`: use `<user>`, `<host>`, `<machine>`, `<person>`, `<work domain>`, `<personal domain>`. Ask before writing a work domain or tunnel name anywhere in the repo.
- Moving a project off its own Caddy changes that project: raise it as more scope, don't fold it in.

## Machine types

The guide's table says which parts apply. On a **work machine**, the tunnel's token, routes, Access applications and zone settings (e.g. Always Use HTTPS) belong to the work account's admins. If the person is one of them, they make the change themselves, as the guide's Admin's guide says; otherwise it's a request to an admin, not something to do with whatever access the person has. Check with the person that the employer allows a root certificate, a system service and `cloudflared` on a managed machine.

## Finishing

Check each part as the guide says, pages in a real browser, then restart and check again. Stop the dev servers, tunnels and browser tabs you started, and say what's still running and why.

# Dev proxy: project plan

**Goal:** an always-on Caddy that gives every dev server a name, never a port number, locally (`<app>.localhost`) and from other devices (Cloudflare Tunnel by default, Tailscale as a personal option). It works for the team on Windows (including Windows + WSL) and macOS, with the dotfiles providing the personal extras.

**Design:** [2026-11-11-dev-proxy-design.md](../specs/2026-11-11-dev-proxy-design.md), which holds the decisions, what the work trial established, and the items still open.

**What this plan is:** the steps between the design and an implementation plan. Each step says what it produces, what it needs first, and when it's done. The implementation plan, written in step 7, covers the code and doc changes themselves.

**Ground rules for every step:**
- nothing is built or run on a live system until its step says so;
- every claim about Caddy, Cloudflare, Tailscale, Microsoft or Homebrew is checked against official docs, or marked unverified;
- every Cloudflare dashboard step is checked against current docs (context7's `/cloudflare/cloudflare-docs`, the page's `index.md`, or Cloudflare's plugin) before it's given;
- Cloudflare's plugin, where installed, is used read-only; changes in Cloudflare are made by the person, or approved by them one at a time;
- decisions go into the design doc as they're made.

## Steps

### 1. Fold the trial docs into the design

- [x] Bring what the design needs from the trial brief (`2026-11-11-caddy-service-trial.md`) and report (`2026-11-11-caddy-service-trial-report.md`) into the design doc:
  - the Windows steps, with their commands and sources;
  - moving a project onto the service;
  - the tunnel admin's guide, including when someone leaves;
  - the IIS switch;
  - the port wildcard;
  - the corrections and the "couldn't check" list;
  - the Tailscale note about `tailscale serve` reaching Caddy.
- [x] Leave out anything about specific work projects.
- [x] Check Cloudflare's docs for whether a tunnel can take a wildcard hostname (design, Still open 6). Ruled out on the shared work domain; possible on the personal domain, with the dashboard side unverified.
- [x] **You:** review the design doc (approved 2026-11-14).
- [x] Delete the brief, the report and the portless brief (2026-11-14).

**Produces:** a design doc that stands on its own without the brief and report.
**Needs:** nothing.
**Done when:** you've reviewed the design doc and deleted the brief and report (and the portless brief, which only they link to).

### 2. Research the macOS steps

- [x] For each Windows step, find the macOS equivalent in official docs (Caddy, Homebrew, Cloudflare, Apple), keeping it as close to the Windows step as possible and noting why wherever it has to differ.
- [x] List what has to be checked on a Mac (e.g. binding ports 80 and 443 under `brew services`, where `caddy trust` looks for its authority).
- [x] **You:** review the macOS section of the design doc (approved 2026-11-14).

**Produces:** the design doc's macOS section, each step with its source, and a checklist for running it on a Mac.
**Needs:** step 1, so the Windows steps it mirrors are settled.
**Done when:** you've reviewed it. Running it on a Mac comes later.

### 3. Research Cloudflare's docs access for agents

- [x] Find what Cloudflare offers coding agents (e.g. an MCP server for its docs, agent skills), and compare it with context7, which is already installed.
- [x] **You:** decide on the proposal below. Accepted 2026-11-14: nothing is added, and the Cloudflare check is in this plan's ground rules and the design's.

**Findings (2026-11-14):**

- **Cloudflare's Claude Code plugin** (`/plugin marketplace add cloudflare/skills`, then `/plugin install cloudflare@cloudflare`; [agent setup](https://developers.cloudflare.com/agent-setup/claude-code/), [cloudflare/skills](https://github.com/cloudflare/skills)):
  - **Skills:** 22, mostly about building on Workers. Only `cloudflare-one` covers Tunnel and Access.
  - **The API server:** it registers Cloudflare's API MCP server (`https://mcp.cloudflare.com/mcp`). That server signs in with OAuth and can make changes in the account (DNS, Zero Trust and the rest).
  - **opencode:** the skills can be copied in by hand; there are no plugin steps.
- **Cloudflare's docs MCP server on its own** (`https://docs.mcp.cloudflare.com/mcp`, [catalog](https://github.com/cloudflare/mcp-server-cloudflare)):
  - **Tested 2026-11-14:** it answers without any login and offers one read-only tool, `search_cloudflare_documentation`, plus a migration helper.
  - **Setting it up:** it would be one entry in the Claude Code and opencode config.
- **Nothing to install:** any docs page can be fetched as Markdown by adding `index.md` to its URL, and there's an index at `https://developers.cloudflare.com/llms.txt` ([docs for agents](https://developers.cloudflare.com/docs-for-agents/)).
- **context7, already enabled here** (`claude/.claude/settings.json`), indexes Cloudflare's docs repo (`/cloudflare/cloudflare-docs`). Asked where tunnel routes are added in the dashboard, it gave the same current steps as Cloudflare's docs server: Networking → Tunnels → Routes → Add route → Published application. That's the very thing the trial's agent got wrong.

**Proposal:**

- **Add nothing for now.** context7 already serves current Cloudflare docs, so the trial's outdated directions most likely came from the agent answering from memory rather than looking them up.
- **Instead, add one line** to the guide and the design's ground rules: check every Cloudflare step against context7 (`/cloudflare/cloudflare-docs`) or the page's `index.md`.
- **Not the plugin:** its API server can change the Cloudflare account. That cuts against the rule that the person does everything in Cloudflare themselves, and the admin's role.
- **If a Cloudflare-specific fallback is wanted later,** the docs server is the light option: no login, read-only, one config entry.
- **Was context7 there?** Most likely it was enabled on the work machine during the trial but not used (2026-11-14). So the gap is that nothing pointed the agent at Cloudflare's docs when it mattered, not a missing tool. Another docs tool would face the same problem, which supports adding nothing and making the check explicit in the ground rules agents work from.

**Revised 2026-11-14, during step 5:**
- **What happened:** the user installed Cloudflare's plugin as a project plugin (`.claude/settings.json`), to look at the personal account, and is keeping it.
- **What it changes:** nothing requires a Cloudflare tool any more, but the plugin is welcome.
- **How agents use it:** read-only, with changes made by the person or approved by them one at a time.
- **Where:** recorded in the design's "Dotfiles and docs" decisions, replacing "no Cloudflare tool is added".

**Produces:** a proposal saying what it is, what it's for, why it beats what's installed (or doesn't), and how it would be added to the Claude Code and opencode config here.
**Needs:** nothing; it can run alongside steps 1 and 2.
**Done when:** you've decided. Nothing is installed without your approval.

### 4. Review the Tailscale exploration

- [x] Review `feature/tailscale` against the design: `tailscale.ps1`, `lib/Tailscale.psm1`, `tests/Tailscale.Tests.ps1`, `tailscale/README.md`, and its links from other docs. Findings below.
- [x] Check it against the herdr and SSH requirements in the design's Goal. Without Tailscale, nothing changes. With it, the Windows Herdr app still reaches WSL locally, and other devices reach the Windows host and each WSL distro. That includes whether more than one distro can work, given distros appear to share one network.
- [x] For each part, say whether to keep it, change it or remove it. For example:
  - the README's dev-server sections predate Caddy on Windows;
  - the Windows OpenSSH steps;
  - whether the script still fits once Caddy is on Windows.
- [x] **You:** check whether the Herdr mobile app can connect on a port other than 22, or through a jump host (the docs don't say). It takes an address (name or IP), a user and a port (2026-11-14).
- [x] **You:** choose A or B below, and approve the keep, change or remove list. B chosen 2026-11-14; its column of the list goes into the implementation plan.

**Findings (2026-11-14):**

- **Multiple WSL distros can't each be a tailnet device.** All WSL 2 distros run in one VM and share one network, so two distros can't both run `tailscaled` as separate devices, or SSH servers on the same port. Microsoft's docs don't say this outright; it comes from a Microsoft maintainer in [WSL issue #4304](https://github.com/microsoft/WSL/issues/4304) and later reports. The exploration's design (WSL as its own device with Tailscale SSH) works for one distro only.
- **Tailscale recommends running it on the Windows host only,** not in WSL 2 ([WSL 2](https://tailscale.com/docs/install/windows/wsl2)). The exploration's README already says so.
- **Tailscale on Windows can forward a port to WSL:**
  - **The command:** `tailscale serve --tcp=<port> tcp://localhost:<port>` forwards a tailnet port to a local TCP server, with SSH named as an example and no admin rights needed ([serve](https://tailscale.com/kb/1242/tailscale-serve)).
  - **What it would allow:** on Windows, it could pass `meeg-laptop:2222` to WSL's existing SSH server on `127.0.0.1:2222` through WSL's localhost forwarding, and a second distro on `2223`.
  - **Not verified:** that it works on Windows, and that it lasts across restarts.
- **herdr-core reaches machines however `ssh` does:** `hc machine add` takes `user@host:2222` or a host from `~/.ssh/config`, so ports and jump hosts work, and `--via <command>` takes any ssh command line.
- **Not documented: what the phone app can take.** Whether the Herdr mobile app can set a port or a jump host isn't covered by [its page](https://herdr.dev/mobile/), which only says it finds machines from the connected computer, its SSH config and your Tailscale devices.

**Two ways to meet the herdr and SSH requirements with Tailscale.** Without Tailscale, neither changes anything.

| | A. WSL as its own tailnet device (as explored) | B. Tailscale on Windows only |
|---|---|---|
| Reaching WSL from other devices | Tailscale SSH on `meeg-laptop-wsl:22`: no keys | WSL's existing SSH server through `meeg-laptop:2222` (`tailscale serve --tcp`), with the phone's key added to WSL |
| More than one distro | No | Yes: one port each |
| Tailscale's advice | Goes against it (packet-size problems) | Follows it |
| What's in the dotfiles | `tailscale.ps1`, its module and tests, plus docs | Docs only (Windows steps), no script |
| The phone | Works: port 22, no key | Needs the app to take a port (or a jump host): **to check** |
| Earlier decision | Matches "WSL stays its own tailnet device" | Reverses it |

**Keep, change or remove, by part:**

| Part | If A | If B |
|---|---|---|
| `tailscale.ps1`, `lib/Tailscale.psm1`, `tests/Tailscale.Tests.ps1` | Keep. Consider dropping `--operator`: it was there so `tailscale serve` worked without `sudo` for dev servers, which now go through Caddy | Remove: nothing runs in WSL. The branch was never run, so no retire step is needed |
| README: How it fits together, Connecting from the phone, Connecting from another computer | Keep, reworded for the dev-proxy design | Rewrite: one device, ports per distro |
| README: Friendly names | Keep; drop the dev-server example (`http://meeg-laptop-wsl:5173`) | Keep, for `meeg-laptop` only |
| README: Tailnet settings | Keep the SSH rule (`accept`) and key expiry. Drop HTTPS Certificates, which only `tailscale serve` over HTTPS needed | Drop the SSH rule (no Tailscale SSH) and HTTPS Certificates; keep key expiry |
| README: WSL section (automated, manual, check) | Keep | Replace with: add the phone's key to WSL, and the `tailscale serve --tcp` step on Windows |
| README: Keep WSL running | Keep | Keep |
| README: Windows (Tailscale, OpenSSH server, keys, herdr-core) | Keep: remote access to the Windows host needs it | Keep |
| README: Dev servers and other services | Remove; link to the dev-proxy docs instead (Caddy on Windows, the Tailscale route's wildcard DNS) | Same |
| README: Not used here (Funnel, Services) | Move the reasons into the design, which already records them | Same |
| README: Removing | Keep, adjusted | Adjust: no WSL steps |
| Links: `AGENTS.md` (script row, Scripts line), `README.md`, `linux/README.md`, `windows/README.md` | Keep; reword `README.md`'s "reach herdr-core and dev servers" for the dev proxy | Remove the script mentions; keep the links to the README |
| Personal names (`meeg-laptop`, `cpmee`, `LAPTOP-LEO2VFVM`) | Use placeholders such as `<host>` and `<user>`, as the dotfiles also run at work and are meant to be reusable | Same |

**Recommendation:** B, if the Herdr mobile app can connect on a port other than 22 (or through a jump host). It follows Tailscale's advice, supports more than one distro, reuses the SSH server WSL already has for the Windows app, and drops the script. If the app can't, A for the one distro, accepting that a second distro can't be reached from the phone.

**Produces:** a keep, change or remove list for you to approve.
**Needs:** step 1.
**Done when:** you've approved the list. The changes themselves go into the implementation plan. Don't run the script before then.

### 5. Spike the Tailscale route on the personal laptop

- [x] **You:** buy the personal domain and add it to Cloudflare. `meeglocal.net`, already in the personal account.
- [x] Settle where the Caddy build with the Cloudflare plugin comes from, and where the API token lives (design, Still open 2 and 3). Research these first and ask before installing anything.
- [x] Try `tailscale serve --tcp` on Windows to each WSL distro's SSH server, and connect from the phone with its key (design, Still open 12). Tried with the one distro, Debian.
- [x] Try it from the phone. Check whether the phone's and routers' DNS resolve a public name pointing at a tailnet address, and whether Caddy can listen on the tailnet address when it starts before Tailscale has set that address up (Still open 4 and 5).
- [x] **You:** choose what to keep, then undo the rest. Undo everything, and rebuild it from the implementation plan (2026-11-14).
- [x] Undo it all (the change list under step 6). Checked 2026-11-14:
  - **Windows:** no `caddy` service or `C:\Program Files\Caddy`, no Caddy roots in the user's store, nothing listening on 80, 443 or 2019, and Tailscale uninstalled.
  - **Cloudflare:** `meeglocal.net` has no DNS records again.
  - **WSL:** the SSH server is back to the Windows app's key only, on `127.0.0.1:2222`.
  - **Done by the user and not checked from here:** deleting the API token, removing the NextDNS allowlist entry, the phone's settings, and the machine in the Herdr app.
  - **Left behind on purpose:** the Chocolatey Caddy and `cloudflared`.

**Produces:** answers to Still open 2 to 5 and 12, recorded in the design doc, and a list of what the spike changed and how it was undone.
**Needs:** step 4, and the domain.
**Done when:** the answers are in the design doc and the laptop is back as it was, or as you chose.

### 6. Test the hardened alternative

- [x] On the personal laptop, try `admin off` (changes applied by restarting the service; trust by importing `root.crt`) and the config under `C:\Program Files\Caddy\` (design, Still open 7).

**Changes made on the personal laptop (2026-11-14), and how to undo them.** Steps 5 and 6 share this list.

| Change | Undo |
|---|---|
| Caddy 2.11.9 (official zip) in `C:\Program Files\Caddy\`, with `Caddyfile`, `sites\spike.caddy`, `sites\spike2.caddy` and `caddy.log` | As administrator: `Remove-Item -Recurse 'C:\Program Files\Caddy'` (after the service is deleted) |
| Windows service `caddy` (`start= demand`, LocalSystem) | As administrator: `sc.exe stop caddy; sc.exe delete caddy` |
| The service's data, including its local certificate authority: `C:\Windows\System32\config\systemprofile\AppData\Roaming\Caddy` | As administrator: `Remove-Item -Recurse 'C:\Windows\System32\config\systemprofile\AppData\Roaming\Caddy'` |
| Root *Caddy Local Authority - 2026 ECC Root* in the user's Trusted Root store (thumbprint `76DA8A35D5E0D8DEAC38D49A176347637C488D19`) | `certutil -user -delstore Root 76DA8A35D5E0D8DEAC38D49A176347637C488D19` |
| **Step 5:** Caddy rebuilt with `dns.providers.cloudflare` (old binary kept as `caddy.exe.tmp`), plus `sites\tailnet.caddy` | Goes with `C:\Program Files\Caddy` above |
| **Step 5:** the token file, `…\systemprofile\AppData\Roaming\Caddy\cloudflare.token`, and Let's Encrypt account and certificates | Go with the service's data folder above |
| **Step 5:** Cloudflare API token `caddy dns meeglocal.net` (DNS edit and zone read on `meeglocal.net`, expiring by itself) | Delete it in My Profile → API Tokens |
| **Step 5:** DNS record `*.laptop.meeglocal.net` A `100.66.231.9` (DNS only) | Delete it in DNS → Records |
| **Step 5:** Tailscale on Windows (`meeg-laptop`), and the Tailscale app on the phone | Uninstall; remove `meeg-laptop` in the admin console |
| **Step 5:** Tailscale forwards `443` and `2222` (`tailscale serve --bg --tcp=…`) | `tailscale serve reset` |
| **Step 5:** the phone's key `herdr-mobile` in WSL's `~/.ssh/authorized_keys`, and the machine in the Herdr mobile app | Delete that line; remove the machine in the app |
| **Step 5:** `meeglocal.net` on the NextDNS Allowlist; "Use Tailscale DNS" off in the phone's Tailscale app | Remove the entry; turn the setting back on |
| **Step 5:** a Let's Encrypt certificate for `*.laptop.meeglocal.net` | Can't be undone: the name stays in public certificate logs. It expires 2027-02-12 |

The WSL test server has already been stopped and its folder removed (both times). The Chocolatey Caddy and `cloudflared` weren't touched.

**The Host-override check (2026-11-15, design Still open 10), all undone and checked the same day.** Chocolatey's Caddy and `cloudflared` were run, not changed:

| Change | Undo |
|---|---|
| Caddy run as the user with a scratch Caddyfile (`https://myapp.localhost:8443`, admin off), its data in a scratch folder | Stopped; the scratch folder deleted |
| `%APPDATA%\Caddy`, a throwaway local certificate authority that `caddy validate` created, trusted nowhere | Deleted |
| A header-echo server, then a scratch Vite 7 app with `vite` installed in its scratch folder, on `127.0.0.1:3000` | Stopped; the scratch folder deleted |
| Four quick tunnels (`trycloudflare.com` names, gone with the process); no Cloudflare account changes | Stopped |
| One Chrome tab, in an isolated profile, on the tunnel's URL | Closed |

Afterwards nothing listened on 3000 or 8443, no `caddy` or `cloudflared` process was running, `%APPDATA%\Caddy` was gone, and `%USERPROFILE%\.cloudflared` was still empty.

**The Access wildcard and wildcard route check (2026-11-15, design Still open 6 and 14), all undone the same day.** Dashboard changes were made by the user:

| Change | Undo |
|---|---|
| Tunnel `spike` on the personal account, its token saved in `%USERPROFILE%\.cloudflared\spike.token` (never opened) | The user deleted the tunnel; the token file was deleted |
| Access applications `spike alpha` (`*-alpha`), `spike beta` (`beta-*`) and `spike bypass` (`one-alpha`, path `webhook`) | Deleted by the user, the bypass one first |
| Route `*` on the tunnel, and the `*` DNS record of type *Tunnel* it created | Deleted by the user |
| A header-echo server on `127.0.0.1:3000` and `cloudflared tunnel run --token-file`, run as the user | Stopped; the scratch folder deleted |

Afterwards the test names didn't resolve through `1.1.1.1` and requests to them failed to connect, no `cloudflared` was running, nothing listened on 3000, and `%USERPROFILE%\.cloudflared` was empty.

**A fresh start in Cloudflare (2026-11-14, on purpose, not to be undone):**
- **The account as found:** one zone, `meeglocal.net` (registered 2024-01-28, auto-renewing), with no DNS records and no tunnels. It has an Access organisation, `meeg.cloudflareaccess.com`, with no apps.
- **What was removed:** `%USERPROFILE%\.cloudflared\cert.pem`, from an old `cloudflared tunnel login`, deleted unopened. The user is deleting two old "Argo Tunnel" API tokens in the dashboard.

**Produces:** tested steps for the hardened alternative, or the reasons it doesn't work.
**Needs:** step 1. It can share a session with step 5.
**Done when:** the result is in the design doc.

### 7. Write the implementation plan

- [x] Decide the shape of tunnel names on the personal domain (design, Still open 1). `<app>.meeglocal.net`, through a wildcard route (2026-11-14).
- [x] Write the implementation plan with `superpowers:writing-plans`, covering:
  - the Windows reference docs (in `windows/README.md`, `tailscale/README.md` or new files such as `caddy/README.md`);
  - the macOS docs;
  - retiring Caddy in WSL (`Install-Caddy`, `Enable-UnprivilegedLowPorts`, retire steps in `lib/Retire.psm1`, `install.ps1`, `update.ps1`, `linux/README.md`) and its tests;
  - the Tailscale changes from step 4 (option B's column).
- [x] Written: [2026-11-14-dev-proxy-implementation.md](./2026-11-14-dev-proxy-implementation.md) (2026-11-14), reviewed by a fresh subagent, revised, and approved by the user. It's to be carried out later with `/implement-plan`.

**Produces:** an implementation plan in `docs/superpowers/plans/`.
**Needs:** steps 1, 2 and 4 to 6.
**Done when:** you've approved the plan.

### 8. Build

- [x] Carried out [2026-11-14-dev-proxy-implementation.md](./2026-11-14-dev-proxy-implementation.md) with `/implement-plan`, one reviewed task at a time (2026-11-15 to 2026-11-16). Along the way, two live checks on the personal laptop: the tunnel Host override, and one Access application per person with a wildcard tunnel route (change lists under step 6).

**Produces:** `dev-proxy/` and the rewritten `tailscale/` guide, WSL's Caddy and low-ports sysctl retired, and the exploration's Tailscale script removed.
**Needs:** step 7.
**Done when:** the plan's final review is done and you've committed the result.

## Deferred

Record anything deferred here when it's deferred.

- **A second WSL distro over Tailscale** (deferred 2026-11-14, while reviewing the implementation plan):
  - **The limit:** the repo's sshd config (`linux/sshd_config.d/herdr-wsl.conf`) hard-codes port 2222, and the setup step warns on a second distro, because distros share one network.
  - **What it would take:** making the port configurable per distro, with tests, and a Tailscale forward for each (e.g. 2223).
  - **Until then:** the docs cover one distro.

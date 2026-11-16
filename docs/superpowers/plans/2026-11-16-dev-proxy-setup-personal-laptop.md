# Dev proxy: set up the personal laptop

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, run it with `/workflow:implement-plan`, one task at a time.

**Goal:** the dev proxy, its tunnels and the Tailscale route running for real on the personal laptop (Windows 11 + WSL Debian), following the guides, with every difference between the guides and reality fixed in the guides; then the set-up captured so other machines (the work laptop next) can be done the same way.

**Architecture:** the guides are the source of every step: [dev-proxy/README.md](../../../dev-proxy/README.md) and [tailscale/README.md](../../../tailscale/README.md). This plan only orders them for this machine, says what to check after each, and records what changed on the machine with an undo. Almost every step changes a live system, so the person runs administrator commands and every dashboard change; the agent prepares, verifies and updates the docs. The last tasks turn what happened into a "Setting up a machine" section in the guide and a skill that walks an agent through it on any machine.

**Tech stack:** Caddy 2.11.x (Windows service), `cloudflared`, Cloudflare Tunnel and Access, Tailscale, Windows OpenSSH, WSL 2 Debian, PowerShell 7, the repo's `update.ps1`.

**Spec:** [the dev proxy design](../specs/2026-11-11-dev-proxy-design.md), with the two guides above. Earlier spikes on this machine are recorded in the [project plan](./2026-11-14-dev-proxy-project.md), step 6.

## Global Constraints

**Live systems:**
- **Who does what:** the person runs every command that needs administrator rights or `sudo`, and makes every change in Cloudflare's and Tailscale's dashboards and on the phone. The agent gives one clear instruction, waits for "done", then verifies. The agent may run read-only checks, and commands that need no admin rights and change only what the step's change list names.
- **Change lists first:** before a step changes anything, show the exact changes with an undo for each, and wait for approval. Record what was actually changed in [Changes on this machine](#changes-on-this-machine) as it happens.
- **Cloudflare:** check every dashboard step against current docs before giving it: context7 `/cloudflare/cloudflare-docs`, the page's `index.md`, or Cloudflare's plugin, read-only.
- **Processes:** stop dev servers, tunnels, watchers and browser tabs started for a check once it's done, unless the next step needs them; say what's still running and why.

**Secrets:**
- Never ask for, accept, print or write down a token, key or secret, and don't read files that hold them: `~/.cloudflared/*.token`, `cloudflare.token` in the service's data folder, `~/.secrets`. Check that such a file exists with its size only.
- Tokens go from the dashboard into Notepad and straight into their file, as the guides say; never through a terminal or a chat.

**Git:** don't stage, commit, push, stash or switch branches. Each task ends with a checkpoint where the user reviews and commits.

**Docs** (as in the [implementation plan](./2026-11-14-dev-proxy-implementation.md#global-constraints)):
- **Where reality differs from a guide,** fix the guide's step in the same task, and say so at the checkpoint.
- **Labels:** a *docs only* step that now worked becomes *tested*, with what it was tested on if that differs from the guide's opening labels (e.g. "tested on the personal laptop, 2026-11-17"). A step that failed is rewritten, not just relabelled.
- **Names:** no personal values in `dev-proxy/`, `tailscale/` or the skill. In prose use `<user>`, `<host>`, `<machine>`, `<person>`, `<work domain>` and `<personal domain>`; in config files `example.com` and `example.net`. Personal values may appear in this plan, the design and the project plan.
- **Files:** Markdown isn't hard-wrapped; new files use LF; existing files keep their line endings.
- **Checks on each changed README,** from Git Bash: the personal-values check, `grep -rniE "meeg|cpmee|laptop-leo2vfvm|100\.66\.|76DA8A35|tailba65bb|tskey|cfut_" dev-proxy tailscale claude/.claude/local-plugins/dev-proxy`, expected no output; and the link check from the implementation plan, run with `./`-prefixed paths.

**Tests:** if a task changes a script or module, the suite passes: `wsl.exe -d Debian --cd /mnt/c/Users/cpmee/.dotfiles -- pwsh -NoProfile -c 'Invoke-Pester tests -Output Detailed'`, run from the PowerShell tool.

## Review Focus

1. **A restart:** no spike ever restarted Windows. With `start= demand` the service waits for `sc.exe start caddy`, so every name is down after a restart until someone starts it; the Tailscale forwards and WSL's SSH server must come back too. Task 6 restarts and checks each.
2. **Spike leftovers that clash:** an old Caddy root still trusted, an old `*.laptop` DNS record or Tailscale forward pointing at something gone, an old API token near its expiry. Task 1 finds them; each later task starts clean or reuses on purpose.
3. **The DNS filter on this laptop** (NextDNS): the Tailscale names need the allowlist entry, and the certificate may need the propagation lines. The optional steps apply here, and their checks must be run, not assumed.
4. **The hardened set-up with the tailnet site:** never tested together. The site goes in `C:\Program Files\Caddy\sites`, changes need a restart, and `caddy trust` doesn't work, so trusting is by hand.
5. **Ports 80 and 443 already taken** (IIS, or a leftover Caddy in WSL forwarding them): the service fails to start. Task 1 checks what listens; Task 2 removes WSL's Caddy before Task 3 starts the service.

---

### Task 1: Take stock and decide

Read-only: nothing on the machine changes.

**Files:**
- Modify: this plan: [Decisions](#decisions) and the starting rows of [Changes on this machine](#changes-on-this-machine).

**Interfaces:**
- Produces, in [Decisions](#decisions), the values later tasks use: the set-up (default or hardened), so the config and `sites` paths; the start type (`demand` or `auto`); `<host>` and `<machine>`; the test project and its port; and, for each leftover, keep, reuse or reset.

- [x] **Step 1: Inventory, read-only.** For each item, record what's there:
  - **Caddy on Windows:** a `caddy` service (`sc.exe query caddy`), `C:\Program Files\Caddy`, `C:\ProgramData\Caddy`, the service's data folder (existence only), `%APPDATA%\Caddy`, Chocolatey's `caddy` (`choco list caddy`), and *Caddy Local Authority* roots in the user's store (`certutil -user -store Root`, subjects and hashes only).
  - **Ports:** what listens on 80, 443, 2019, 5399 (`Get-NetTCPConnection -State Listen`), and whether IIS is installed (`Get-Service W3SVC`).
  - **WSL:** the `caddy` package, its apt source and keyring, `/etc/sysctl.d/50-unprivileged-ports.conf`, and old roots in `/usr/local/share/ca-certificates/`.
  - **WSL's clone:** whether `~/.dotfiles` in WSL is its own clone, its branch, and how far it is behind `origin` (`git -C ~/.dotfiles status -sb`, `git -C ~/.dotfiles log -1 --oneline`). `update.ps1` pulls and syncs the clone it runs from, so this decides where Task 2 runs it.
  - **`cloudflared`:** which ones are installed (Chocolatey's, winget's or an MSI), and what's in `%USERPROFILE%\.cloudflared` (names only).
  - **Tailscale:** installed or not, `tailscale status` for this device's name, `tailscale serve status`, and whether "Run unattended" is on.
  - **SSH:** the `sshd` service, the firewall rule's remote addresses, and the number of lines in `administrators_authorized_keys` (count only).
  - **The spikes' change lists** (project plan, step 6): for each row, whether it's still in place. Rows that need a dashboard (the `*.laptop` DNS record, the API token and its expiry, the NextDNS allowlist, the tunnel and Access apps) are a question to the person.
- [x] **Step 2: Recommend, then ask.** Bring the person a short list:
  - **Default or hardened set-up:** recommend hardened, as this machine will hold the Cloudflare token ([tailscale/README.md](../../../tailscale/README.md#dev-servers-by-name-on-the-tailnet), step 3).
  - **Start type:** `auto` if IIS isn't installed, so the names survive a restart; `demand` if it is.
  - **Each leftover:** keep, reuse or reset, e.g. reuse the NextDNS allowlist entry, reset an old API token.
  - **Chocolatey's `caddy` and `cloudflared`:** keep or uninstall. The guides use Caddy's zip and `cloudflared` from winget, so two copies on `PATH` can mean the wrong one runs.
  - **Which clone runs `update.ps1` in WSL:** WSL's own `~/.dotfiles` once it has this branch's changes (merged and pulled), or the Windows clone through `/mnt/c`. Recommend WSL's own clone, as that's how the machine is normally updated.
  - **`<host>`, `<machine>`** and **the test project** (a real project, or a scratch Vite app).
- [x] **Step 3: Record** the answers in [Decisions](#decisions), and the leftovers kept or reused in [Changes on this machine](#changes-on-this-machine) as "already present".
- [x] **Step 4: Checkpoint.** The user reviews and commits (suggested: `plan the personal laptop set-up`). (Left for the user.)

### Task 2: Retire Caddy in WSL

**Files:**
- Modify, only if something differs: `linux/README.md` (`### Caddy`), `dev-proxy/README.md` (Optional: clean up the old Caddy, "Old roots in WSL").

- [x] **Step 1: Preview.** The agent runs `pwsh ./update.ps1 -WhatIf` in WSL from the clone recorded in [Decisions](#decisions) (e.g. `wsl.exe -d Debian --cd <clone> -- pwsh ./update.ps1 -WhatIf`). Expected: exit 0, and under "Retiring removed tools..." the `~ sudo apt remove -y caddy`, `~ sudo rm -f …` and `~ sudo sysctl -w net.ipv4.ip_unprivileged_port_start=1024` lines.
- [x] **Step 2: Run it.** The person runs `pwsh ./update.ps1` in a WSL terminal, in the same clone, answering `sudo` and sync's prompts.
- [x] **Step 3: Verify.** `dpkg -l caddy` shows `rc` (removed, config kept: `apt remove` keeps `/etc/caddy`, `/var/lib/caddy` and the `caddy` user, as [linux/README.md](../../../linux/README.md#caddy) says); the apt source, keyring and sysctl file are gone; `sysctl net.ipv4.ip_unprivileged_port_start` prints `1024`; a second `update.ps1 -WhatIf` prints `- Caddy is not installed` and `- The low-ports sysctl is not set`. Then, optionally, the person runs `sudo apt purge -y caddy`, after which `dpkg-query -W caddy` finds no package and the user, group and folders are gone (done here).
- [x] **Step 4: Old roots in WSL,** if Task 1 found any: the person runs the two commands in the guide's "Old roots in WSL". Verify none are left in `/usr/local/share/ca-certificates/`, and that `curl -sI https://example.com` in WSL still works. (Not needed here: Task 1 found the folder empty. It's still empty, and `curl` returns `HTTP/2 200`.)
- [x] **Step 5: Checkpoint** (left for the user) (suggested: `retire caddy in wsl on the personal laptop`).

### Task 3: The dev proxy on Windows

**Files:**
- Modify: `dev-proxy/README.md`, where a step differs or a *docs only* step now worked (e.g. step 3's `start= auto`, the hardened set-up's steps for a first install).

**Interfaces:**
- Consumes: [Decisions](#decisions): the set-up, start type and test project.
- Produces: the running service with the test project's `.localhost` site, which Tasks 4 and 5 add public and tailnet names to.

- [ ] **Step 1: Install and configure** with the guide's [Windows](../../../dev-proxy/README.md#windows-also-windows--wsl) steps 1–3, or for the hardened set-up its [steps 1–2](../../../dev-proxy/README.md#optional-the-hardened-set-up), with the start type from Decisions. Verify: `sc.exe query caddy` shows `RUNNING`; something listens on `127.0.0.1:443` and `127.0.0.1:80`, and on `127.0.0.1:2019` only for the default set-up.
- [ ] **Step 2: Trust the root:** step 5, or the hardened set-up's step 4. Verify: `certutil -user -store Root` lists the service's root, with the same `Cert Hash(sha1)` as `certutil -dump` of the service's `root.crt` (run by the person as administrator).
- [ ] **Step 3: The test project's site,** from [example.caddy](../../../dev-proxy/example.caddy) with only the local name for now (step 4), plus its hosts entry (step 6). Start its dev server on `127.0.0.1:<port>`. Verify:
  - `curl.exe --ssl-no-revoke -s -o NUL -w "%{http_code}" https://<app>.localhost` prints `200`;
  - in Chrome, the page loads with no certificate warning, and an edit shows up through hot reload;
  - `https://5173.port.localhost` reaches a server on 5173 if one runs, and `https://2019.port.localhost` returns `403` (step 7).
- [ ] **Step 4: Old Caddy clean-up,** as decided in Task 1: the guide's [old roots on Windows](../../../dev-proxy/README.md#optional-clean-up-the-old-caddy) (keeping the service's root), Chocolatey's `caddy` with `choco uninstall caddy` if chosen, and its `%APPDATA%\Caddy`. If the guide has no step for Chocolatey's Caddy, add one beside winget's.
- [ ] **Step 5: Update the guide** with every difference found, and the labels of what now worked, then run the checks in the Global Constraints.
- [ ] **Step 6: Checkpoint.** Leave the dev server stopped. (Suggested: `set up the dev proxy on the personal laptop`.)

### Task 4: Tunnels on the personal domain

**Files:**
- Modify: `dev-proxy/README.md`: [Tunnels](../../../dev-proxy/README.md#tunnels) (installing `cloudflared` with winget rather than the MSI) and [Personal domain](../../../dev-proxy/README.md#personal-domain), where they differ or now worked; the full `*` Access application is still *docs only* there; and Removing's `cloudflared` uninstall.
- Modify: the design, "Still open" 14, if the full `*` Access application behaves differently from the partial wildcards tested.

**Interfaces:**
- Consumes: Task 3's service and test project.

- [ ] **Step 1: Install `cloudflared` with winget** (decided in Task 1): change the guide to recommend `winget install --id Cloudflare.cloudflared` (*not in Cloudflare's docs*, which list the MSI winget installs), updated with `winget upgrade --id Cloudflare.cloudflared`, and its Removing step to `winget uninstall --id Cloudflare.cloudflared`. Then the person runs `choco uninstall cloudflared` as administrator and the winget install. Verify: `Get-Command cloudflared -All` lists only the winget-installed copy, and `cloudflared --version` runs.
- [ ] **Step 2: A quick tunnel** at the test project's dev server, as in [One-off sharing](../../../dev-proxy/README.md#one-off-sharing-a-quick-tunnel), then once more with `--allowed-mail` and the person's email. Verify from the phone on mobile data: the page loads; with `--allowed-mail`, it asks for the PIN first. Stop it.
- [ ] **Step 3: The machine's tunnel,** as the [Admin's guide](../../../dev-proxy/README.md#admins-guide-cloudflare-tunnel) with the Personal domain differences: the tunnel named for `<machine>`, its token into `%USERPROFILE%\.cloudflared\<tunnel>.token`, one Access application on subdomain `*`, the `*` route to `http://127.0.0.1:5399`, and Always Use HTTPS if it isn't on. Verify the token file's size only.
- [ ] **Step 4: The public site:** add `http://<app>.<personal domain>:5399` to the test project's sites file, apply it (reload, or restart for the hardened set-up), add the name to the dev server's host check, and run the tunnel. Verify:
  - with curl and no redirects followed, `https://<app>.<personal domain>/` returns `302` to the Access login, and `https://<personal domain>/` (the bare domain) doesn't reach the dev server;
  - in a browser, after the PIN, the page loads, hot reload works, and the app sees `X-Forwarded-Proto: https`;
  - `http://<app>.<personal domain>` redirects to `https://`.
- [ ] **Step 5: Stop the tunnel** and record in the guide whether anything should keep it running. The guide only runs it in a terminal; a service for `cloudflared` is out of scope, so if the person wants one, record it in the project plan's Deferred list.
- [ ] **Step 6: Update the guide and the design,** then the checks. **Checkpoint** (suggested: `set up the personal tunnel on the personal laptop`).

### Task 5: Tailscale

**Files:**
- Modify: `tailscale/README.md` and `tailscale/tailnet.caddy`, where they differ or now worked; above all the hardened set-up with the tailnet site (Review Focus 4).

**Interfaces:**
- Consumes: [Decisions](#decisions) (`<host>`, `<machine>`, the leftovers to reuse); Task 3's service.

- [ ] **Step 1: Tailscale and SSH to Windows,** per the guide's [Windows](../../../tailscale/README.md#windows-host) sections, reusing what Task 1 found in place. Verify from the phone (Herdr app) or another tailnet device: `ssh <user>@<host>` logs in with a key, and a password login is refused.
- [ ] **Step 2: SSH to WSL** and the phone, per [SSH to WSL](../../../tailscale/README.md#ssh-to-wsl) and [Connecting from the phone](../../../tailscale/README.md#connecting-from-the-phone). Verify: the Herdr app shows WSL's terminals through port 2222.
- [ ] **Step 3: Dev servers by name,** per the guide's [seven steps](../../../tailscale/README.md#dev-servers-by-name-on-the-tailnet), with the optional DNS-filter steps for NextDNS where they apply. Verify:
  - `& 'C:\Program Files\Caddy\caddy.exe' list-modules` includes `dns.providers.cloudflare`;
  - the service starts, and the log (the person adds the logging block while setting up) shows the wildcard certificate obtained;
  - from the phone with Tailscale on, `https://<app>.<machine>.<personal domain>` loads with a valid certificate; with Tailscale off, it doesn't resolve or doesn't connect;
  - the `.localhost` site from Task 3 still works.
- [ ] **Step 4: Update the guide** (and `tailnet.caddy`'s comments if needed), then the checks. **Checkpoint** (suggested: `set up tailscale on the personal laptop`).

### Task 6: Restart and check

**Files:**
- Modify: whichever guide's claims the restart contradicts; the design's "Still open" 5 and 12, which say a full restart wasn't tried.

- [ ] **Step 1: Restart Windows,** then log in. With `start= demand`, the person starts the service first, as the guide says.
- [ ] **Step 2: Check each:**
  - the `caddy` service is running (by itself with `start= auto`), and `https://<app>.localhost` loads once the dev server runs;
  - `tailscale serve status` shows both forwards, and the phone reaches WSL on 2222 and `https://<app>.<machine>.<personal domain>`;
  - WSL's SSH server is back once WSL starts (and the "Keep WSL running" task, if it was added);
  - the tunnel runs again with the same command.
- [ ] **Step 3: Record** the results in the guides (replace "A full Windows restart wasn't tried") and the design. **Checkpoint** (suggested: `check the dev proxy after a restart`).

### Task 7: Setting up a machine: the guide

**Files:**
- Modify: `dev-proxy/README.md`: a new `## Setting up a machine` section after the opening (before `## Windows (also Windows + WSL)`), linked from the opening paragraph.

**Interfaces:**
- Produces: the `#setting-up-a-machine` anchor, which Task 8's skill follows.

- [ ] **Step 1: Write the section,** from what Tasks 1–6 actually did. It's for the person (or an agent helping them) setting up any machine:
  - **Before you start:** what to check is already there (the Task 1 inventory, as a checklist), and the choices to make: default or hardened, start type (IIS or not), and which parts apply.
  - **Which parts apply:** a table of machine types: a personal Windows machine (everything, Tailscale included), a work Windows machine (the local names and the person's tunnel, with the token from the work account's admin; no Tailscale), and a Mac (the macOS guide, with its checklist).
  - **The order:** retire WSL's Caddy (for WSL machines), the dev proxy, old-Caddy clean-up, tunnels, Tailscale, then a restart check, each linking to its section, with the one check that shows it worked.
  - **When something differs from the guide:** fix the guide, as the repo's docs are the record.
- [ ] **Step 2: Review** as Task 4, Step 4 of the implementation plan: the personal-values and link checks; every link and anchor resolves; nothing in it is specific to this laptop.
- [ ] **Step 3: Checkpoint** (suggested: `add setting up a machine to the dev proxy guide`).

### Task 8: Setting up a machine: the skill

A skill, so an agent on another machine follows the same way of working: take stock read-only, decide with the person, change lists with an undo, one instruction at a time, verify, and fix the guide where reality differs. It points at the guide for every step rather than repeating it, so there's one place to keep current.

**Files:**
- Create: `claude/.claude/local-plugins/dev-proxy/.claude-plugin/plugin.json`: `{"name": "dev-proxy", "version": "0.1.0", "description": "Setting up and checking the dev proxy, its tunnels and its Tailscale route on a machine", "author": {"name": "Chris Meagher"}}`.
- Create: `claude/.claude/local-plugins/dev-proxy/skills/setting-up-a-machine/SKILL.md` (name *provisional*: `dev-proxy:setting-up-a-machine`).
- Modify: `opencode/.config/opencode/opencode.jsonc`: add `"@DOTFILES@/claude/.claude/local-plugins/dev-proxy/skills"` to the skills list, beside the others.

**Interfaces:**
- Consumes: Task 7's `#setting-up-a-machine` section.

- [ ] **Step 1: Load `superpowers:writing-skills`** and follow it, including its baseline test: a subagent asked to "set up the dev proxy on this machine" without the skill, briefed with the repo's guardrails and told to describe what it would do rather than do it. Note where it goes wrong (e.g. runs admin commands itself, skips the inventory, makes dashboard changes, reads a token file).
- [ ] **Step 2: Write the skill.** Its description says when to use it (setting up, moving or checking the dev proxy, tunnels or Tailscale route on a machine). Its body:
  - **First:** read the guide's [Setting up a machine](../../../dev-proxy/README.md#setting-up-a-machine), and take stock read-only;
  - **Rules:** the Global Constraints of this plan that hold on any machine: who does what, change lists with an undo, secrets, Cloudflare docs checks, processes;
  - **Recording:** where reality differs, fix the guide; keep a list of the machine's changes with undos for the person (in a plan, if one is being followed);
  - **Machine types:** personal, work and Mac, pointing at the guide's table, with the work machine's differences (the token comes from the account's admin; nothing in the work account is changed by the person unless they're its admin).
- [ ] **Step 3: Test it** the same way as the baseline, with the skill loaded. Expected: the subagent's described approach follows the rules the baseline broke. Close each gap in the skill and re-test, as `writing-skills` says.
- [ ] **Step 4: Check it loads:** in a new Claude Code session, the skill is listed as `dev-proxy:setting-up-a-machine`; opencode lists it too after a sync (`pwsh ./sync.ps1 -NoPull`, run by the person if it needs to prompt).
- [ ] **Step 5: Checkpoint** (suggested: `add a skill for setting up the dev proxy on a machine`).

### Task 9: Finish

**Files:**
- Modify: the project plan: a step 9, "Set up the personal laptop", ticked, linking to this plan, with this plan's [Changes on this machine](#changes-on-this-machine) as its change list.
- Modify: the design's "Where things stand": the personal laptop is set up, and the guide and skill exist for other machines.

- [ ] **Step 1: Update the project plan and the design** as listed.
- [ ] **Step 2: A fresh-eyes review** by a subagent that hasn't seen the conversation, of everything this plan changed, briefed with this plan, the guardrails (no secrets, no git changes, no live systems: read-only) and the Global Constraints. Check each finding, report those that hold with fixes, and fix them once the user agrees.
- [ ] **Step 3: List what was raised and deferred** during the plan, for the user to decide on.
- [ ] **Step 4: Checkpoint** (suggested: `record the personal laptop set-up`).

---

## Decisions

Filled in by Task 1.

| Decision | Value | Why |
|---|---|---|
| Set-up | Hardened | The machine will hold the Cloudflare DNS token; the cost (an administrator restart for each sites change, trusting by hand once) was accepted |
| Config and `sites` paths | `C:\Program Files\Caddy\Caddyfile`, `C:\Program Files\Caddy\sites\` | The hardened set-up's paths |
| Start type | `auto` | IIS (W3SVC) isn't installed, so the names survive a restart |
| `<host>` (tailnet device name) | `meeg-laptop` | As in the spikes; the Windows hostname is `LAPTOP-LEO2VFVM` |
| `<machine>` (label in tailnet names) | `laptop` | `<app>.laptop.meeglocal.net`, as in the spikes |
| Test project and port | A scratch Vite app on `127.0.0.1:5173`, in the scratchpad, deleted at the end | No real project needed to test the set-up |
| Chocolatey's `caddy` / `cloudflared` | Uninstall both: `caddy` in Task 3, `cloudflared` in Task 4 | Caddy comes from the guide's zip, `cloudflared` from winget, so only one copy of each is on `PATH` |
| How `cloudflared` is installed | winget (`Cloudflare.cloudflared`), not the MSI | The same MSI from Cloudflare's GitHub releases, hash-checked by winget, and `winget upgrade` keeps it current (it doesn't update itself on Windows). Cloudflare's downloads page lists only the MSI and exe, so the guide marks it "not in Cloudflare's docs". Decided 2026-11-16 |
| Clone that runs `update.ps1` in WSL | WSL's own `~/.dotfiles` | Already on `feature/dev-proxy` at `c64c7da`, level with `origin`, so it has the retire steps; it's how the machine is normally updated |
| WSL's Caddy retire step | Stays `apt remove`, not `purge` (decided 2026-11-16, Task 2) | Purge deletes `/etc/caddy`, which may hold hand edits; the Linux guide says how to purge |
| Spike leftovers in dashboards and on the phone | All gone; start clean | The person confirmed every undo in the project plan's step 5–6 lists was done (API token, `*.laptop` record, `meeg-laptop` in Tailscale, NextDNS allowlist, the phone's Tailscale app and setting, the Herdr machine) |

## Changes on this machine

Every change made while following this plan, with its undo. Leftovers that Task 1 kept or reused are listed as "already present".

| Task | Change | Undo |
|---|---|---|
| 1 | Already present: Chocolatey's `caddy` 2.11.9 and `cloudflared` 2026.10.7, on `PATH` (to be uninstalled in Tasks 3 and 4) | — |
| 1 | Already present: WSL's `caddy` 2.11.9 package (service disabled, inactive), its apt source and keyring, and `/etc/sysctl.d/50-unprivileged-ports.conf` (`ip_unprivileged_port_start = 80`), to be retired in Task 2 | — |
| 1 | Already present: Windows' OpenSSH server installed, `sshd` stopped and Manual, no `sshd_config` or `administrators_authorized_keys` yet; firewall rule `OpenSSH-Server-In-TCP` allowing any address (set up in Task 5) | — |
| 1 | Already present: WSL's SSH server on `127.0.0.1:2222` with one key (the Windows Herdr app's) | — |
| 2 | WSL: `update.ps1` retired Caddy: `apt remove caddy`, its apt source and keyring deleted, `/etc/sysctl.d/50-unprivileged-ports.conf` deleted and `ip_unprivileged_port_start` back to `1024`. The same run did the routine updates (apt upgrade, tools, pull, sync) | Re-add Caddy's apt source and keyring per [Caddy's Debian install](https://caddyserver.com/docs/install#debian-ubuntu-raspbian), then `sudo apt install caddy`; `echo 'net.ipv4.ip_unprivileged_port_start=80' \| sudo tee /etc/sysctl.d/50-unprivileged-ports.conf && sudo sysctl --system` |
| 2 | WSL: `sudo apt purge -y caddy`: the `caddy` user and group, `/etc/caddy` (the pre-dev-proxy `Caddyfile`), `/var/lib/caddy` (the old WSL Caddy's local authority, trusted nowhere) and `/var/log/caddy` deleted | None needed; the install above recreates the user and folders |

## Addenda

Anything raised and deferred while carrying out this plan goes here, at the moment it's deferred, unless it belongs in the project plan's Deferred list.

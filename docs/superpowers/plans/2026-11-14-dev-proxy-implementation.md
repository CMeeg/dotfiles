# Dev proxy Implementation Plan

> **For agentic workers:** this plan is carried out with the user's `/implement-plan` skill (`workflow:implement-plan`), task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire Caddy and the low-ports setting from WSL, remove the Tailscale exploration's script, and write the reference docs for the dev proxy (Caddy as a Windows service, Cloudflare Tunnel, the optional personal Tailscale route), so the set-up can be followed by hand now and scripted later.

**Architecture:**
- **Code:** two new retire steps in `lib/Retire.psm1`, following the existing ones, and matching removals from `install.ps1`.
- **Docs:** a new reference folder, `dev-proxy/` (not in `dotfiles.json`, like `windows/`), with a README and the Caddyfiles it describes. `tailscale/` is rewritten for Tailscale on Windows only, with its own example site file.

The Tailscale exploration's script, module and tests go.

**Tech Stack:** PowerShell 7, Pester 6, Markdown, Caddyfile.

**Spec:** `docs/superpowers/specs/2026-11-11-dev-proxy-design.md` (the design). The project plan is `docs/superpowers/plans/2026-11-14-dev-proxy-project.md`. Read the design's Decisions, "Set-up as tested", macOS and "Still open" sections before any docs task.

## Global Constraints

**Working tree:**
- **Where to edit:** all edits are made in the Windows clone, `C:\Users\<user>\.dotfiles`. WSL's `~/.dotfiles` is a separate, older clone; don't edit it or test from it.
- **Running tests and scripts:** run them in WSL against the Windows clone. The test command, called "the test command" below:

  ```
  wsl.exe -d Debian --cd /mnt/c/Users/<user>/.dotfiles -- pwsh -NoProfile -c 'Invoke-Pester tests -Output Detailed'
  ```

  A single file is the same, with `Invoke-Pester tests/<File>.Tests.ps1`. Scripts run the same way, e.g. `wsl.exe -d Debian --cd /mnt/c/Users/<user>/.dotfiles -- pwsh ./install.ps1 -WhatIf`.

**Repo conventions** (`AGENTS.md`):
- **Script style:** PowerShell modules start with `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`, with 2-space indents.
- **Dry runs:** `-WhatIf` must change nothing. Commands that change things go through `Invoke-Step`, and paths in them through `ConvertTo-ShellArgument`.
- **Retire steps:** a retire step only removes, never installs. It prints one `Write-Skip` line when there's nothing to remove, is called from `Invoke-RetireSteps`, and is exported.
- **Tests:** Pester tests put fakes first on `PATH`, so real `sudo`, `apt`, `systemctl` or `sysctl` are never called. Paths under `/etc` are parameters with the real path as the default, so tests can pass temp paths (as `Invoke-WslSshd -ConfigDir` does).
- **No test may depend on the machine's real `/etc` or installed packages.** Tests that call `Invoke-RetireSteps` in-process mock the new steps.

**Files:**
- **Markdown:** no hard-wrapping; each paragraph or list item is one line.
- **Line endings:** new files use LF; keep existing files' line endings (check with `grep -c $'\r' <file>`).
- **Comments:** they say why, in the present tense, with no history and no references to plans.

**Git:** don't stage, commit, push or switch branches. Delete files with plain file operations, not `git rm`. Each task ends with a checkpoint where the user reviews and commits.

**Docs content:**
- **Voice:** this is the user's own personal dotfiles repo. Write everything in that context, for the user and anyone they choose to share it with or hand a step to. Don't frame any part as written for a colleague or a team. Where the design says "the team" (e.g. its Goal), write "if several people use this set-up" instead.
- **Commands:** use only commands and settings covered by official docs (Caddy, Microsoft, Cloudflare, Tailscale, Homebrew, Vite, Next), each linked. Anything kept from the current docs that isn't, e.g. `conhost.exe --headless` in "Keep WSL running", is checked or labelled *not in official docs*.
- **Labels:** mark each step *tested* or *docs only*, as the design does. Steps that exist only because of a DNS filter are labelled *optional* and say when they apply, with NextDNS as the example. Tailscale steps are *optional, personal*.
- **Names:** no personal names or values. In prose, use `<user>`, `<host>`, `<machine>`, `<person>`, `<work domain>` and `<personal domain>`. In config files, which must parse, use `example.com` for the work domain and `example.net` for the personal domain.
- **Cloudflare:** check every Cloudflare dashboard step against current docs before writing it: context7 `/cloudflare/cloudflare-docs`, the page's `index.md`, or the Cloudflare plugin, read-only.
- **Secrets:** never put a token, key or secret in a file, test or doc example.

**The personal-values check:** each docs task runs it on the folders it wrote. Expected: no output.

```
grep -rniE "meeg|cpmee|laptop-leo2vfvm|100\.66\.|76DA8A35|tailba65bb|tskey|cfut_" <folder>
```

**The link check:** each docs task runs it on each README it wrote. Expected: no output. It checks files only; anchors are checked by hand against the slugs in Task 4's Interfaces.

```
pwsh -c '$f = "<folder>/README.md"; (Select-String -Path $f -Pattern "\]\((?!http)([^)#]+)" -AllMatches).Matches | % { $_.Groups[1].Value } | ? { -not (Test-Path (Join-Path (Split-Path $f) $_)) }'
```

**Exact values from the design:**
- **Ports:** public-name port `5399`, WSL SSH `2222`, admin API `2019` (never on a port allow-list).
- **Names:**
  - work tunnel names `<person>-<app>.<work domain>`;
  - personal tunnel names `<app>.<personal domain>`;
  - Tailscale names `<app>.<machine>.<personal domain>`;
  - local names `<app>.localhost`.
- **Windows paths:**
  - config `C:\ProgramData\Caddy\` (default) or `C:\Program Files\Caddy\` (hardened);
  - binary `C:\Program Files\Caddy\caddy.exe`;
  - service data `C:\Windows\System32\config\systemprofile\AppData\Roaming\Caddy`.

## Review Focus

1. **A machine where Caddy was never installed** (a fresh or plain Linux machine): both retire steps print one skip line each and call nothing. Tests: "Caddy: skips when not installed", "low ports: skips when not set".
2. **A half-removed Caddy** (package gone, apt source left): the leftover apt source and keyring are removed, so `apt update` stops fetching Caddy's repo. Test: "Caddy: removes a leftover apt source and keyring when the package is gone".
3. **A sysctl file someone has added to:** it's left in place, with a warning, and the kernel setting isn't touched. Test: "low ports: leaves a file with other settings".
4. **The running kernel after the file is removed:** ports below 1024 need root again straight away, not after the next restart. Test: "low ports: removes the file and restores the default now" asserts the `sysctl -w` call.
5. **A reader using Windows PowerShell 5.1 or Command Prompt for an `sc.exe create` line:** the docs say only PowerShell 7 was tested and give the Command Prompt form, for both the default and the hardened set-up. Checked in Task 4's review step.

---

### Task 1: Retire Caddy in WSL

**Files:**
- Modify: `lib/Retire.psm1`: add `Invoke-RetireCaddy`, call it last in `Invoke-RetireSteps`, add it to `Export-ModuleMember`.
- Modify: `install.ps1`: delete `Test-SystemdUnit` (lines 153–158, used only by Caddy), `Install-Caddy` (160–185) and the `Install-Caddy` call (293). `update.ps1` has no Caddy code and needs no change.
- Modify: `linux/README.md`, `### Caddy` (lines 170–185): replace only the install and disable-service bullets (lines 172–179). Task 2 handles the sysctl bullets and the N.B.
- Test: `tests/Retire.Tests.ps1`, under `Context 'tools'`, plus the existing "second run is a no-op".

**Interfaces:**
- Produces: `Invoke-RetireCaddy [-AptSource <string> = '/etc/apt/sources.list.d/caddy-stable.list'] [-Keyring <string> = '/usr/share/keyrings/caddy-stable-archive-keyring.gpg']`.
- Consumes: `Test-AptInstalled` (`lib/Tools.psm1`), `Invoke-Step`, `Write-Skip`, `Write-Ok`, `ConvertTo-ShellArgument` (`lib/Common.psm1`).

- [x] **Step 1: Write the failing tests** in `tests/Retire.Tests.ps1` → `Context 'tools'`. The file's `BeforeEach` already fakes `sudo` (logging `sudo $*` to `$log`) and `dpkg-query` (not installed).

```powershell
It 'Caddy: removes the package, its apt source and keyring' {
  New-FakeCommand 'dpkg-query' 'echo "install ok installed"'
  Write-FixtureFile "$tmp/caddy-stable.list" "deb x`n"
  Write-FixtureFile "$tmp/caddy.gpg" 'k'
  $out = Invoke-Captured { Invoke-RetireCaddy -AptSource "$tmp/caddy-stable.list" -Keyring "$tmp/caddy.gpg" }
  $calls = Get-Content $log
  $calls | Should -Contain 'sudo apt remove -y caddy'
  $calls | Should -Contain "sudo rm -f $tmp/caddy-stable.list $tmp/caddy.gpg"
  $out | Should -Match '✓ Caddy removed'
}

It 'Caddy: removes a leftover apt source and keyring when the package is gone' {
  Write-FixtureFile "$tmp/caddy-stable.list" "deb x`n"
  Invoke-Captured { Invoke-RetireCaddy -AptSource "$tmp/caddy-stable.list" -Keyring "$tmp/caddy.gpg" } | Out-Null
  $calls = @(Get-Content $log)
  $calls | Should -Not -Contain 'sudo apt remove -y caddy'
  $calls | Should -Contain "sudo rm -f $tmp/caddy-stable.list"
}

It 'Caddy: skips when not installed' {
  $out = Invoke-Captured { Invoke-RetireCaddy -AptSource "$tmp/none.list" -Keyring "$tmp/none.gpg" }
  "$log" | Should -Not -Exist
  $out | Should -Match '  - Caddy is not installed'
}

It 'Caddy: dry-run changes nothing' {
  New-FakeCommand 'dpkg-query' 'echo "install ok installed"'
  Write-FixtureFile "$tmp/caddy-stable.list" "deb x`n"
  Set-DryRun $true
  $out = Invoke-Captured { Invoke-RetireCaddy -AptSource "$tmp/caddy-stable.list" -Keyring "$tmp/caddy.gpg" }
  "$log" | Should -Not -Exist
  "$tmp/caddy-stable.list" | Should -Exist
  $out | Should -Match '~ sudo apt remove -y caddy'
}

It 'Invoke-RetireSteps runs the Caddy step' {
  Mock Invoke-RetireCaddy -ModuleName Retire {}
  Invoke-Captured { Invoke-RetireSteps } | Out-Null
  Should -Invoke Invoke-RetireCaddy -ModuleName Retire -Times 1 -Exactly
}
```

In the existing "second run is a no-op", add `Mock Invoke-RetireCaddy -ModuleName Retire {}` before the first `Invoke-RetireSteps`, so it doesn't read this machine's real apt state.

- [x] **Step 2: Run the tests to check they fail.** Use the test command for `tests/Retire.Tests.ps1`. Expected: the five new tests fail, as `Invoke-RetireCaddy` isn't recognised (the mock can't bind to it).

- [x] **Step 3: Implement `Invoke-RetireCaddy` in `lib/Retire.psm1`.**
  - **Skip:** if the package isn't installed and neither path exists, `Write-Skip 'Caddy is not installed'`.
  - **Remove the package:** run `Invoke-Step 'sudo apt remove -y caddy'` when it's installed.
  - **Remove the leftovers:** when either path exists, run `Invoke-Step "sudo rm -f <paths>"`. The paths are the existing ones only, in the order AptSource then Keyring, each through `ConvertTo-ShellArgument` and space-separated.
  - **Finish:** `Write-Ok 'Caddy removed — the dev proxy runs it on Windows (see dev-proxy/README.md)'`.
  - **Comment:** one line of why above the function: Caddy runs as a Windows service for the dev proxy, so the apt package goes, with its apt repo and keyring.
  - **Wire it up:** call it after `Invoke-RetireStatuslinesMods` in `Invoke-RetireSteps`, and export it.

- [x] **Step 4: Remove Caddy from `install.ps1`.** Delete `Test-SystemdUnit`, `Install-Caddy` and the `Install-Caddy` call. Leave `Enable-UnprivilegedLowPorts` for Task 2.

- [x] **Step 5: Edit `linux/README.md`'s `### Caddy`.** Keep the heading. Replace lines 172–179 (the install and disable-service bullets) with:
  - Caddy runs on Windows as the dev proxy and serves dev servers in WSL too: see [dev-proxy/README.md](../dev-proxy/README.md). That file is written in Task 4.
  - WSL doesn't install it, and the retire steps remove an apt-installed Caddy, with its apt repo and keyring.
  - `apt remove` keeps `/etc/caddy` and `/var/lib/caddy`; `sudo apt purge caddy` removes them too.
  - Caddy's old local certificate authority roots stay in the trust stores: see the dev proxy's clean-up step, in Task 4's `## Moving a project onto the service`.
  - Left on purpose, as they're small and other tools may use them: `debian-keyring`, `debian-archive-keyring` and `apt-transport-https`, installed alongside Caddy's apt repo, and `libnss3-tools` in the base packages.

- [x] **Step 6: Run the tests to check they pass.** Use the test command. Expected: all pass, including the five new tests and "second run is a no-op".

- [x] **Step 7: Check the dry run.** Run `install.ps1 -WhatIf` as in the Global Constraints. Expected:
  - it exits 0, with no `Installing Caddy...` line;
  - under "Retiring removed tools...", one of `- Caddy is not installed`, `~ sudo apt remove -y caddy` or `~ sudo rm -f …`.

- [x] **Step 8: Checkpoint.** The user reviews and commits (suggested: `retire caddy in wsl`).

### Task 2: Retire the low-ports sysctl

**Files:**
- Modify: `lib/Retire.psm1`: add `Invoke-RetireUnprivilegedLowPorts`, call it after `Invoke-RetireCaddy` in `Invoke-RetireSteps`, and export it.
- Modify: `install.ps1`: delete `Enable-UnprivilegedLowPorts` and its call.
- Modify: `linux/README.md`, `### Caddy`: the sysctl bullets and the `setcap` N.B. left by Task 1.
- Test: `tests/Retire.Tests.ps1`, under `Context 'tools'`, plus "second run is a no-op".

**Interfaces:**
- Produces: `Invoke-RetireUnprivilegedLowPorts [-ConfPath <string> = '/etc/sysctl.d/50-unprivileged-ports.conf']`.
- Consumes: as Task 1, plus `Write-Warn`.

- [x] **Step 1: Write the failing tests.**

```powershell
It 'low ports: removes the file and restores the default now' {
  Write-FixtureFile "$tmp/50-unprivileged-ports.conf" "net.ipv4.ip_unprivileged_port_start=80`n"
  $out = Invoke-Captured { Invoke-RetireUnprivilegedLowPorts -ConfPath "$tmp/50-unprivileged-ports.conf" }
  $calls = Get-Content $log
  $calls | Should -Contain "sudo rm -f $tmp/50-unprivileged-ports.conf"
  $calls | Should -Contain 'sudo sysctl -w net.ipv4.ip_unprivileged_port_start=1024'
  $out | Should -Match '✓ Low-ports sysctl removed'
}

It 'low ports: removes a file with comments and blank lines around the setting' {
  Write-FixtureFile "$tmp/50-unprivileged-ports.conf" "# ports`n`n  net.ipv4.ip_unprivileged_port_start=80  `n"
  Invoke-Captured { Invoke-RetireUnprivilegedLowPorts -ConfPath "$tmp/50-unprivileged-ports.conf" } | Out-Null
  Get-Content $log | Should -Contain "sudo rm -f $tmp/50-unprivileged-ports.conf"
}

It 'low ports: leaves a file with other settings' {
  Write-FixtureFile "$tmp/50-unprivileged-ports.conf" "net.ipv4.ip_unprivileged_port_start=80`nvm.swappiness=10`n"
  $out = Invoke-Captured { Invoke-RetireUnprivilegedLowPorts -ConfPath "$tmp/50-unprivileged-ports.conf" }
  "$log" | Should -Not -Exist
  $out | Should -Match '  ! .*50-unprivileged-ports\.conf has other settings — left in place'
}

It 'low ports: skips when not set' {
  $out = Invoke-Captured { Invoke-RetireUnprivilegedLowPorts -ConfPath "$tmp/none.conf" }
  "$log" | Should -Not -Exist
  $out | Should -Match '  - The low-ports sysctl is not set'
}

It 'low ports: dry-run changes nothing' {
  Write-FixtureFile "$tmp/50-unprivileged-ports.conf" "net.ipv4.ip_unprivileged_port_start=80`n"
  Set-DryRun $true
  $out = Invoke-Captured { Invoke-RetireUnprivilegedLowPorts -ConfPath "$tmp/50-unprivileged-ports.conf" }
  "$log" | Should -Not -Exist
  $out | Should -Match '~ sudo rm -f'
}

It 'Invoke-RetireSteps runs the low-ports step' {
  Mock Invoke-RetireCaddy -ModuleName Retire {}
  Mock Invoke-RetireUnprivilegedLowPorts -ModuleName Retire {}
  Invoke-Captured { Invoke-RetireSteps } | Out-Null
  Should -Invoke Invoke-RetireUnprivilegedLowPorts -ModuleName Retire -Times 1 -Exactly
}
```

Then:
- in "second run is a no-op", add `Mock Invoke-RetireUnprivilegedLowPorts -ModuleName Retire {}` beside Task 1's mock;
- in Task 1's "Invoke-RetireSteps runs the Caddy step", add the same mock.

- [x] **Step 2: Run the tests to check they fail.** Use the test command for `tests/Retire.Tests.ps1`. Expected: the six new tests fail, as the function doesn't exist.

- [x] **Step 3: Implement `Invoke-RetireUnprivilegedLowPorts`.**
  - **Skip:** if the file doesn't exist, `Write-Skip 'The low-ports sysctl is not set'`.
  - **Leave it if it's been added to:** the file's lines, trimmed, without blank lines and lines starting with `#`, must equal exactly `net.ipv4.ip_unprivileged_port_start=80` (case-sensitive). Otherwise `Write-Warn "$ConfPath has other settings — left in place"` and return, without touching the kernel setting.
  - **Remove:** otherwise run `Invoke-Step "sudo rm -f <quoted path>"`, then `Invoke-Step 'sudo sysctl -w net.ipv4.ip_unprivileged_port_start=1024'` (1024 is the kernel's default), then `Write-Ok 'Low-ports sysctl removed: ports below 1024 need root again'`.
  - **Comment:** one line of why: nothing in WSL binds ports 80 or 443, as Caddy runs on Windows.

- [x] **Step 4: Remove `Enable-UnprivilegedLowPorts`** and its call from `install.ps1`.

- [x] **Step 5: Edit `linux/README.md`'s `### Caddy`.** Replace the sysctl bullets and the `setcap` N.B. with one bullet: the retire steps also remove the low-ports sysctl (`/etc/sysctl.d/50-unprivileged-ports.conf`) and put the kernel's default back, unless the file holds other settings.

- [x] **Step 6: Run all tests, and check the dry run** as in Task 1, Steps 6–7. Expected:
  - all tests pass;
  - no `Allowing unprivileged processes...` line;
  - a low-ports line under the retire steps.

- [x] **Step 7: Checkpoint.** The user reviews and commits (suggested: `retire the low-ports sysctl`).

### Task 3: Remove the Tailscale exploration's script

**Files:**
- Delete: `tailscale.ps1`, `lib/Tailscale.psm1`, `tests/Tailscale.Tests.ps1` (plain deletes).
- Modify: `AGENTS.md`:
  - the **Scripts** line goes back to `install.ps1`, `update.ps1`, `sync.ps1` and `retire.ps1`;
  - delete the `tailscale.ps1` row of **Key Commands**.
- Modify: `linux/README.md`: replace `### Tailscale (optional)` (lines 120–122) with one line. Tailscale runs on Windows, and forwards to WSL's SSH server and to the dev proxy: see [tailscale/README.md](../tailscale/README.md).

**Interfaces:** none. Nothing else imports `Tailscale.psm1`.

- [x] **Step 1: Delete the three files, and edit `AGENTS.md` and `linux/README.md`** as listed.
- [x] **Step 2: Run the tests.** Use the test command. Expected: all pass, with no Tailscale tests.
- [x] **Step 3: Check nothing still points at the removed files.**

  ```
  grep -rn "tailscale\.ps1\|Tailscale\.psm1" --exclude-dir=docs --exclude-dir=.git --exclude=README.md . ; grep -n "tailscale\.ps1" README.md linux/README.md windows/README.md
  ```

  Expected: no output. `tailscale/README.md` still mentions the script until Task 8.
- [x] **Step 4: Checkpoint.** The user reviews and commits (suggested: `remove the tailscale script, which wsl no longer needs`).

### Task 4: The dev proxy on Windows: config files and guide

**Files:**
- Create: `dev-proxy/Caddyfile`. The top file exactly as in the design's "Set-up as tested → Windows" step 2: `default_bind 127.0.0.1 [::1]`, `skip_install_trust`, `servers { trusted_proxies static 127.0.0.1/32 ::1/128 }` and `import sites/*.caddy`, with the comments shown there.
- Create: `dev-proxy/sites/ports.caddy`. The design's step 7, with the allow-list `5173.port.localhost 8080.port.localhost` and a comment: never add `2019`.
- Create: `dev-proxy/example.caddy`. A template for a project's sites file, kept outside `sites/` so it never loads as a live site:
  - the design's step 4: `myapp.localhost` → `127.0.0.1:3000`;
  - `http://person-myapp.example.com:5399` → `127.0.0.1:3000`, with a comment saying it's the public name reached through the person's tunnel.
- Create: `dev-proxy/README.md`. The Windows guide, with the sections below.

**Interfaces:**
- Produces: the README's headings, in this order once Tasks 6–7 have added theirs, with their GitHub anchors:

  | Heading | Anchor | Added by |
  |---|---|---|
  | `## Windows (also Windows + WSL)` | `#windows-also-windows--wsl` | Task 4 |
  | `## Windows + WSL differences` | `#windows--wsl-differences` | Task 4 |
  | `## Tunnels` | `#tunnels` | Task 6 |
  | `## Admin's guide: Cloudflare Tunnel` | `#admins-guide-cloudflare-tunnel` | Task 6 |
  | `## Personal domain` | `#personal-domain` | Task 6 |
  | `## macOS` | `#macos` | Task 7 |
  | `## If you also use IIS` | `#if-you-also-use-iis` | Task 4 |
  | `## Moving a project onto the service` | `#moving-a-project-onto-the-service` | Task 4 |
  | `## Optional: the hardened set-up` | `#optional-the-hardened-set-up` | Task 4 |
  | `## Optional: DNS filters` | `#optional-dns-filters` | Task 4 |
  | `## Removing` | `#removing` | Task 4 |

- Produces: `dev-proxy/Caddyfile`, `dev-proxy/sites/ports.caddy` and `dev-proxy/example.caddy`, which the guide tells the reader to copy or adapt.

- [x] **Step 1: Write the three Caddyfiles** as above. Use tabs inside them, as `caddy fmt` does.

- [x] **Step 2: Check Caddy accepts them.** On Windows, with any Caddy (e.g. Chocolatey's), copy `example.caddy` into a scratch copy of `sites/` and run `caddy adapt --config <scratch>/Caddyfile`. Expected: exits 0, and the JSON contains `127.0.0.1:5399` and `"127.0.0.1:3000"`. `import` resolves relative to the Caddyfile, whatever folder the command runs from.

- [x] **Step 3: Write `dev-proxy/README.md`.**
  - **Opening:**
    - what the dev proxy is, in two sentences, from the design's Goal, in this repo's voice;
    - a table of a project's names: local, work tunnel, personal tunnel, Tailscale;
    - links to `#tunnels` and to `../tailscale/README.md`.
  - **`## Windows (also Windows + WSL)`:** steps 1–9 and 11 of the design's "Set-up as tested → Windows", in order, with their commands, notes, labels and source links.
    - Step 2 copies `dev-proxy/Caddyfile` and `dev-proxy/sites/ports.caddy`, rather than typing them.
    - Step 4 starts each project's file from `dev-proxy/example.caddy`.
    - Step 6 includes Windows' `curl.exe --ssl-no-revoke`.
    - Step 9 (tunnels) is a one-line link to `#tunnels`.
    - Step 10 (IIS) and step 11 (clean-up) are one-line links to `#if-you-also-use-iis` and `#moving-a-project-onto-the-service`.
  - **`## Windows + WSL differences`:** from the design's section of that name, plus its "Assessed on paper" line on WSL's mirrored networking.
  - **`## If you also use IIS`:** step 10's switch commands and notes, plus the design's "Assessed on paper" lines on HTTP.sys and on Caddy in front of IIS, as one short paragraph.
  - **`## Moving a project onto the service`:** from the design's section of that name, then step 11's optional clean-up of old roots and the per-user Caddy, for both Windows and WSL.
  - **`## Optional: the hardened set-up`:** from the design's "Still open" 7 (tested):
    - `admin off`, with the config, `sites` and the log under `C:\Program Files\Caddy\`;
    - `sc.exe create` with the quoted `--config "C:\Program Files\Caddy\Caddyfile"`, in PowerShell 7 and in Command Prompt form;
    - changes applied by `sc.exe stop caddy; sc.exe start caddy`;
    - trusting by copying `root.crt` out as administrator, then `certutil -user -addstore Root <file>`;
    - when to choose it: the design's "Windows service" decision.
  - **`## Optional: DNS filters`:** the design's "DNS-filter steps are optional" decision. Each step says when it applies; for the Windows proxy on its own, nothing applies. Tasks 7–8 add theirs.
  - **`## Removing`:**
    - stop and delete the service (`sc.exe stop caddy; sc.exe delete caddy`);
    - remove `C:\Program Files\Caddy` and the config folder (`C:\ProgramData\Caddy`, unless hardened);
    - remove the service's data folder;
    - remove any hosts entries added in step 6;
    - remove the root: find its thumbprint with `certutil -user -store Root`, looking for *Caddy Local Authority* ([certutil](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil)), then `certutil -user -delstore Root <thumbprint>`;
    - for tunnels, link to `#tunnels`, which Task 6 gives its own removal lines.

- [x] **Step 4: Review the README against the Global Constraints, and Review Focus 5.**
  - **Personal values and links:** run the personal-values check on `dev-proxy`, and the link check on `dev-proxy/README.md`.
  - **Labels:** every step has a label and a source link.
  - **Other shells:** both `sc.exe create` lines say only PowerShell 7 was tested, and give the Command Prompt form.

- [x] **Step 5: Checkpoint.** The user reviews and commits (suggested: `add the dev proxy's windows guide and config`).

### Task 5: Check two tunnel improvements (design, "Still open" 9 and 10)

**Files:**
- Modify: `docs/superpowers/specs/2026-11-11-dev-proxy-design.md`: "Still open" 9 and 10 get their findings, with sources and a verdict.
- Modify, only if Step 3 runs: `docs/superpowers/plans/2026-11-14-dev-proxy-project.md`, the change list under step 6, with what Step 3 changed and how it was undone.

**Interfaces:**
- Produces, for Task 6, one answer each:
  - **Item 9:** can each person add their own tunnel routes without the admin?
  - **Item 10:** can a route send requests in as the app's `.localhost` name?

  Each answer is "document it", "document it as unverified" or "leave it out", decided with the user in Step 4.

- [x] **Step 1: Research item 9 (each person managing their own tunnel's routes)** in Cloudflare's docs ([granular permissions](https://developers.cloudflare.com/tunnel/guides/granular-permissions/) and the roles reference it links to). Find out:
  - **The role:** which resource-scoped role lets a member add and remove published application routes on one tunnel.
  - **DNS:** whether adding a route also needs DNS permission on the zone, as the dashboard creates each route's DNS record.
  - **Other people's names:** whether anything stops that member routing a hostname that belongs to someone else, e.g. another person's `<person>-<app>` prefix.

  Use the docs, or the Cloudflare plugin read-only; change nothing in any account. Testing it would need a second member in an account, so it isn't tested here. If the docs leave it open, the verdict is "needs a test by the work account's admins".

- [x] **Step 2: Research item 10 (skipping the project changes with a Host header override)** in Cloudflare's [origin parameters](https://developers.cloudflare.com/tunnel/reference/origin-parameters/). Find out:
  - **Which settings:** whether `httpHostHeader`, `originServerName`, `noTLSVerify` and `caPool` can each be set for a remotely-managed tunnel's route in the dashboard, or only in a config file.
  - **The route:** the settings it would need: Service URL `https://127.0.0.1:443`, Host header `<app>.localhost`, origin server name `<app>.localhost`, and either `noTLSVerify` or a CA pool. A CA pool would need a copy of Caddy's root that `cloudflared` can read, as the original sits where only administrators can read it.
  - **The equivalent quick-tunnel flags,** for a live check: `cloudflared tunnel --url … --http-host-header … --origin-server-name … --no-tls-verify`.

- [x] **Step 3 (only with the user's approval): check item 10 live on the personal laptop.**
  - **Prepare:** bring the user an exact change list with an undo for each, as in project plan steps 5 and 6.
  - **The set-up:** the default Windows Caddy service with one `.localhost` site, a throwaway dev server, and a quick tunnel using the Step 2 flags. No Cloudflare account changes.
  - **Check:**
    - the page loads through the quick tunnel's URL;
    - which Host and `X-Forwarded-*` headers the app sees;
    - whether a dev server's host check still needs changing;
    - what happens to links the app builds from the Host.
  - **Afterwards:** undo everything, and check it's undone.

- [x] **Step 4: Record and decide.** Write the findings into "Still open" 9 and 10, with sources, dates and labels (*tested* or *docs only*). Then ask the user, for each item, whether Task 6 documents it, documents it as unverified, or leaves it out. Record their answer in the design.

- [x] **Step 5: Checkpoint.** The user reviews and commits (suggested: `check two tunnel improvements`).

### Task 6: Tunnels: the person's guide and the admin's guide

**Files:**
- Modify: `dev-proxy/README.md`: add `## Tunnels`, `## Admin's guide: Cloudflare Tunnel` and `## Personal domain`, after `## Windows + WSL differences` and in the order of Task 4's table. Add tunnel lines to `## Removing`.

**Interfaces:**
- Consumes: Task 4's headings and anchors, and Task 5's two answers. If item 9 is documented, it goes in `## Admin's guide: Cloudflare Tunnel`; if item 10 is, it goes in `## Tunnels`, under regular access. Either way, they're written as the design records them and labelled to match.
- Produces: the `#tunnels`, `#admins-guide-cloudflare-tunnel` and `#personal-domain` anchors.

- [x] **Step 1: Check each Cloudflare dashboard step against current docs**, as in the Global Constraints. Note each page's URL and the date checked; any step that no longer matches is written as the docs now say, and marked so.

- [x] **Step 2: Write `## Tunnels`.** Take the design's "Reaching dev servers from other devices" decision (two options, by how long the access is needed) and step 9:
  - **One-off sharing:** a quick tunnel to the dev server, with `--http-host-header`, its limits and risks. Label the two claims that come from an article, not Cloudflare's docs.
  - **Whether quick tunnels are allowed:** where several people use this set-up under one organisation, checking first is that organisation's call (design, "Still open" 8).
  - **Regular access:**
    - installing `cloudflared`, the token file, `cloudflared tunnel run --token-file`, and what arrives at the app;
    - the dev server's host check (Vite `server.allowedHosts`, Next `allowedDevOrigins`);
    - the public-name site on port `5399` in the project's sites file;
    - why `trusted_proxies` is in the top file.
  - **Removing a tunnel:** stop `cloudflared`, delete the token file, and uninstall `cloudflared` if it's no longer wanted. Add these to `## Removing`.

- [x] **Step 3: Write `## Admin's guide: Cloudflare Tunnel`.**
  - **Content:** the design's admin's guide (setting a person up, Access with a Bypass path, Always Use HTTPS, when someone leaves, `cert.pem`), as checked in Step 1.
  - **The dedicated account:** a domain used this way lives in a Cloudflare account of its own. For the work domain this is still to be confirmed (design, "Still open" 13), so say that.
  - **For anyone following the guide, agents included:** the dashboard changes often, so check every step against current docs before following it (context7 `/cloudflare/cloudflare-docs`, or the page's `index.md`). Where Cloudflare's plugin is installed, agents use it read-only, and changes are made by the person or approved by them one at a time. This is from the design's "Dotfiles and docs" decisions.

- [x] **Step 4: Write `## Personal domain`.**
  - **The wildcard route:** `*.<personal domain>` → the machine's tunnel → Caddy on `http://127.0.0.1:5399`, behind one wildcard Access app. A new app needs only its sites-file entry: `http://<app>.<personal domain>:5399`.
  - **Fallback:** the design's "Still open" 6. The dashboard's support for wildcard routes is unverified, so the fallback is one route per app with the same names.
  - **Verify while writing:** if the dashboard can be checked read-only (the Cloudflare plugin or the docs), record what it shows. Otherwise label it *docs only, unverified*.

- [x] **Step 5: Review as Task 4, Step 4**, adding: every dashboard step names the docs page it was checked against, and each anchor link matches Task 4's table.

- [x] **Step 6: Checkpoint.** The user reviews and commits (suggested: `add the dev proxy's tunnel guides`).

### Task 7: macOS guide

**Files:**
- Modify: `dev-proxy/README.md`: add `## macOS` where Task 4's table puts it, and macOS lines in `## Optional: DNS filters` and `## Removing`.

**Interfaces:**
- Consumes: Task 4's Windows steps, which the macOS steps follow one for one.
- Produces: the `#macos` anchor.

- [x] **Step 1: Write `## macOS`** from the design's macOS section:
  - **Steps:** the eleven steps, each with its reason for differing from Windows, labelled *docs only*.
  - **The service:** the user service (`brew services start caddy`), with `sudo brew services` only as the fallback the design's decision allows.
  - **Checklist:** the design's "Checklist for a Mac", under `### To check on a Mac`.
  - **Opening line:** it's untested, and the checklist is for whoever first runs it on a Mac.
- [x] **Step 2: Review as Task 4, Step 4.**
- [x] **Step 3: Checkpoint.** The user reviews and commits (suggested: `add the dev proxy's macos guide`).

### Task 8: Tailscale on Windows (optional, personal)

**Files:**
- Rewrite: `tailscale/README.md`.
- Create: `tailscale/tailnet.caddy`. The spike's final site file, with placeholders that still parse:
  - **The site:** `*.laptop.example.net { tls { dns cloudflare {file.C:/Windows/System32/config/systemprofile/AppData/Roaming/Caddy/cloudflare.token} } … }`.
  - **No `bind`:** a comment says why. Tailscale forwards port 443, and a bound tailnet address stops Caddy starting while Tailscale is down.
  - **Optional lines:** `propagation_delay 30s` and `propagation_timeout -1`, commented out, with a comment saying they're optional and needed only when a DNS filter blocks port 53.
  - **Routing:** a `@app host myapp.laptop.example.net` → `reverse_proxy 127.0.0.1:3000` handle, and `respond 404` for other names.
- Modify: `README.md`'s index:
  - **Add:** a `dev proxy` bullet, "names for dev servers on Windows and WSL, locally and from other devices", linking to `./dev-proxy/README.md`.
  - **Reword `tailscale`:** "(optional, personal): reach this machine, its WSL distro and its dev servers from your phone or other computers".
- Modify: `windows/README.md`:
  - **`### tailscale (optional)`:** reword to match.
  - **New `### dev proxy`:** after `### herdr app`, linking to `../dev-proxy/README.md`, and noting the IIS section.
  - **The WSL key's note (line 42):** it says the key "only works against the localhost-only sshd in WSL". Add that with Tailscale's port 2222 forward, that SSH server is also reachable from the tailnet (see `../tailscale/README.md`).

**Interfaces:**
- Consumes: `dev-proxy/README.md`'s `#windows-also-windows--wsl` and `#optional-dns-filters` anchors.

- [x] **Step 1: Rewrite `tailscale/README.md`.** Use the design's "Tailscale runs on Windows only" decision and "Still open" items 2–5 and 12 (all tested). Each current heading is kept, rewritten or dropped as below:

  | Current heading | What happens |
  |---|---|
  | How it fits together | Rewrite: Tailscale on Windows only. The Windows host is reached on port 22; WSL on a forwarded port; dev servers by name through the dev proxy. The Windows Herdr app's local link to WSL is unchanged. |
  | Friendly names | Keep, for the Windows host only. Drop the WSL and dev-server examples. |
  | Tailnet settings | Rewrite: Disable key expiry only. No SSH rule and no HTTPS Certificates, as neither Tailscale SSH nor `tailscale serve` HTTPS is used. |
  | WSL: Automated, Manual, Check | Drop; replaced by "SSH to WSL" below. |
  | Keep WSL running | Keep, with `conhost.exe --headless` checked against Microsoft's docs or labelled *not in official docs*. |
  | Windows: Tailscale | Keep. Add `winget install --id Tailscale.Tailscale`, the tray login, `tailscale set --hostname=<host>`, and the "Run unattended" tip. |
  | Windows: OpenSSH server | Keep. Reword its intro, which mentions Tailscale SSH. |
  | Windows: Keys | Keep, but fix the line saying WSL doesn't need the phone's key. Under this design, it goes in WSL's `authorized_keys` too (see "SSH to WSL"). |
  | Windows: herdr-core, Check | Keep. |
  | Connecting from the phone | Rewrite: the Tailscale app (keep the store links), then the Herdr app's order. Keep the "skip `debian-wsl`" and "Spaces only show where the Herdr app runs" notes. |
  | Connecting from another computer | Rewrite: `ssh -p 2222 <user>@<host>`, and `hc machine add <user>@<host>:2222`. |
  | Dev servers and other services | Replace with "Dev servers by name on the tailnet" below. |
  | Not used here | Drop. |
  | Removing | Rewrite, as item 9 below. |

  New sections:
  - **SSH to WSL:**
    - `tailscale serve --bg --tcp=2222 tcp://127.0.0.1:2222`;
    - the Herdr app's order: add the machine (address, user, port `2222`); add the key it shows to `~/.ssh/authorized_keys` in WSL; then **Connect again**.
    - **Security note:** the forward makes WSL's SSH server reachable from every tailnet device, and the server sees each connection as coming from `127.0.0.1`. Key login only, as the server is set up for, matters more.
  - **Dev servers by name on the tailnet:**
    - the DNS-only `*.<machine>.<personal domain>` record (shown as "DNS only - reserved IP");
    - the API token (Zone → Zone → Read, Zone → DNS → Edit, one zone, an expiry), saved straight into the token file in the service's data folder from Notepad run as administrator;
    - `caddy add-package github.com/caddy-dns/cloudflare`, with the service stopped, and `caddy upgrade` for updates (both experimental);
    - copying `tailscale/tailnet.caddy` into `sites` and restarting;
    - `tailscale serve --bg --tcp=443 tcp://127.0.0.1:443`;
    - checking from the phone.
    - **Security note:** the 443 forward lets any tailnet device reach every site Caddy serves on loopback, if it asks for that name, including `.localhost` sites and the port wildcard, not just the tailnet names.
  - **Optional: DNS filters:** each step says when it applies, with NextDNS as the example, and links to `../dev-proxy/README.md#optional-dns-filters`:
    - allowlist the domain if the filter has rebinding protection;
    - uncomment the propagation lines if a filter app blocks port 53;
    - turn off "Use Tailscale DNS" on Android if the phone has a Private DNS hostname (the phone then uses addresses rather than Tailscale names).
  - **Item 9, Removing:**
    - `tailscale serve reset`;
    - `tailnet.caddy` out of `sites`, then restart Caddy. The plugin build stays until Caddy itself is removed (dev proxy, `#removing`);
    - in Cloudflare: delete the DNS record and the token;
    - the token file;
    - `winget uninstall --id Tailscale.Tailscale`, and remove the machine in Tailscale's admin console;
    - the phone's key in WSL, and the machine in the Herdr app;
    - the optional DNS-filter changes: the allowlist entry, and "Use Tailscale DNS" back on;
    - the Windows lines kept from the current Removing section: stop sshd, put the firewall rule back, remove the keys, unregister "Keep WSL running";
    - a note that the Let's Encrypt name stays in public certificate logs.

- [x] **Step 2: Check Caddy parses `tailscale/tailnet.caddy`.**
  - **With the plugin:** `caddy adapt --config tailscale/tailnet.caddy` exits 0. A Caddy with the plugin can be made by running `caddy add-package` on a scratch copy of a Caddy binary.
  - **Without it:** it fails with "module not registered: dns.providers.cloudflare". That error stops parsing, so the rest of the file goes unchecked.
  - **Record** which was run.

- [x] **Step 3: Edit `README.md` and `windows/README.md`** as listed.

- [x] **Step 4: Review as Task 4, Step 4,** with the personal-values check and the link check on `tailscale` too, adding:
  - **No script left:** `grep -rn "tailscale\.ps1" --exclude-dir=docs --exclude-dir=.git .` gives no output.
  - **Nothing outdated:** no step *uses* `meeg-laptop-wsl`, Tailscale SSH or `--operator`, though the text may explain why they aren't used.
  - **Anchors:** each one links to a heading in Task 4's table.

- [x] **Step 5: Checkpoint.** The user reviews and commits (suggested: `rewrite the tailscale guide for tailscale on windows only`).

### Task 9: Finish

**Files:**
- Modify: `docs/superpowers/specs/2026-11-11-dev-proxy-design.md`:
  - **"Where things stand":** what was built, with links to `dev-proxy/README.md` and `tailscale/README.md`, and that the exploration's script is gone.
  - **Two stale lines:** in the "Tailscale runs on Windows only" decision, `tcp://localhost:2222` becomes `tcp://127.0.0.1:2222`, as tested. In the "Windows service" decision, "Neither is tested yet" becomes a pointer to "Still open" 7, which records the test.
  - **Cloudflare's docs since the trial** (found in Task 6, Step 1): "Set-up as tested" step 9 and its admin's guide get a note on what the docs now say, keeping what was tested. The changes: Access's button is **Add public hostname** (not *Public DNS*); Cloudflare recommends creating the Access application before the route; creating a tunnel has no connector type to choose; **Refresh token** doesn't cut off a `cloudflared` already connected; the run-parameters page no longer says `--token` or `TUNNEL_TOKEN` take precedence over `--token-file`; and quick tunnels' docs now cover `--allowed-mail`, the 200-request limit and the lack of Server-Sent Events. `dev-proxy/README.md` already follows the docs.
- Modify: `docs/superpowers/plans/2026-11-14-dev-proxy-project.md`: add a step 8, "Build", ticked, linking to this plan. Record anything deferred during the work in its "Deferred" section at the time it's deferred.

- [x] **Step 1: Run the full test suite.** Use the test command. Expected: all pass. Then run `install.ps1 -WhatIf` and `update.ps1 -WhatIf` as in the Global Constraints. Expected: both exit 0 and change nothing.
- [x] **Step 2: Update the design and the project plan** as listed.
- [x] **Step 3: Get a fresh-eyes review.** A subagent that hasn't seen the conversation reviews the branch. Brief it with what changed, what it's for, the Global Constraints, and the guardrails: no secrets, no git changes, no live systems, nothing run for real. Check each finding, and report the ones that hold, with fixes.
- [x] **Step 4: List what was raised and deferred** during the plan, for the user to decide on.
- [x] **Step 5: Checkpoint.** The user reviews and commits (suggested: `record the dev proxy as built`).

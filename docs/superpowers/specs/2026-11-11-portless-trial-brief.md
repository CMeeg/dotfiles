# Trial brief: replacing per-project `caddy run` with portless

This brief is for an agent working on a development machine where some projects start their own Caddy (`caddy run` with a project `Caddyfile`) to serve local HTTPS names. Your job is to find out whether [portless](https://github.com/vercel-labs/portless) can replace that, try it on one project, and report back. It's a trial: change as little as possible, and leave everything easy to undo.

## Why

The machine is set up so that projects can run their own Caddy:

- Caddy's systemd service is disabled, so it doesn't hold ports 80/443.
- `net.ipv4.ip_unprivileged_port_start=80` (in `/etc/sysctl.d/50-unprivileged-ports.conf`) lets ordinary processes bind ports 80 and up, so `caddy run` works without `sudo`.

On Linux and WSL machines, a dotfiles repo usually applies this (`install.ps1` → `Install-Caddy` and `Enable-UnprivilegedLowPorts`). Check whether that's the case here.

The longer-term plan, so you know what to look out for:

- Caddy will run again as an always-on service, listening on the machine's Tailscale address only, with a wildcard certificate for a domain the user controls (e.g. `*.work.example.com`).
- It forwards requests to portless, which listens on `127.0.0.1` and routes each name to the dev server it started.
- Per-project `caddy run` on 80/443 would clash with that, hence this trial.

You don't need to set up any of the longer-term pieces: no Tailscale, DNS, domain or Caddy service changes. Only the local part.

## Ground rules

- **Secrets:** never ask for, print, copy or write down a token, key, password or other secret, and don't open files that hold them (`.env.local`, `.env` files with real values, `~/.secrets`, credential stores). If you need to know whether an env file mentions a hostname, ask the user rather than reading it.
- **Git:** don't stage, commit, push, stash, switch branches, or run `git mv`/`git rm` in any repository. Leave every change in the working tree for the user to review.
- **Ask before:**
  - installing anything, including `npm install -g portless`. Say what it is, that it's pre-1.0, and that it needs Node 24 or later;
  - anything that needs `sudo` or administrator rights;
  - anything that changes the system's trust store or hosts file. portless's first run adds its own certificate authority to the Linux trust store, and on WSL to the Windows user's store too, and keeps a block in `/etc/hosts`;
  - editing any file in a project.

  This is a work machine, so the user may need to check company policy first.
- **Live and shared systems:** don't touch shared environments, remote services, DNS, cloud resources, or other people's data. Everything here is local to this machine.
- **Processes:** stop every dev server, proxy and container you start once you've finished with it, including `portless proxy stop`. Never leave a project's own Caddy and the portless proxy competing for port 443. If you need to leave something running, say what and why.
- **Undo:** keep a list of every change you make and how to reverse it. `portless clean` removes portless's certificate authority, its `/etc/hosts` block, its state and any startup service; `npm uninstall -g portless` removes the tool.

## Steps

### 1. Take stock (read-only)

For each project that has a `Caddyfile` or runs `caddy run`, record:

- **How it starts:** a package script, Makefile, Docker Compose, Aspire, a shell script, or by hand.
- **What the Caddyfile does:**
  - the site names (e.g. `app.localhost`, `app.test`, `*.app.test`);
  - how TLS is set up (`tls internal`, its own certificates);
  - each `reverse_proxy` target and port;
  - any routing by path (`handle_path`, `route`), headers, `file_server`, redirects, and anything more unusual.
- **Where the names are used outside the Caddyfile,** in tracked config only: app settings, OAuth callback URLs, allowed origins (CORS), cookie domains, and dev-server host allowlists such as Vite's `server.allowedHosts`.

Also note:
- the OS and whether it's WSL;
- the Node version;
- whether Caddy's service is disabled;
- whether the `sysctl` above is set.

### 2. Install portless and check it (with the user's go-ahead)

- `npm install -g portless`, then `portless doctor`.
- Stop any running project Caddy first: portless's proxy wants port 443 on `127.0.0.1`.

### 3. Try one project

Pick the simplest project, with the user's agreement, and get it working through portless under the same name its Caddyfile uses, so the app's config doesn't need to change. Map the Caddyfile like this:

| What the Caddyfile does | What to use with portless |
|---|---|
| A dev server (Node or anything that reads `PORT`, or Vite, Astro, Angular, Wrangler and others that portless passes `--port` to) | `portless run` or `portless <name> <command>` |
| A service on a fixed port, e.g. a container or a non-Node server | `portless alias <name> <port>` |
| Docker Compose services | `portless compose up` (routes `<service>.<project>.localhost`) |
| A name outside `.localhost`, e.g. `app.test` | `--tld test` on the proxy (several TLDs can be listed) |
| Several services on one name, split by path | No direct equivalent: portless routes by name. Note it as a gap, and say whether giving each service its own name would work |
| Headers, redirects, static files, other Caddy features | Note each as a gap |

Commands and flags are in portless's docs: the [README](https://github.com/vercel-labs/portless), and `commands.mdx` and `configuration.mdx` under `apps/docs/content/docs/` in that repo. Check the docs rather than relying on this table. The table was written from them on 2026-11-11, and portless changes quickly before 1.0.

Then check it in a browser, not just with `curl`:

- the page loads over HTTPS with no certificate warning;
- hot reload and websockets work;
- logging in, OAuth callbacks and cookies work;
- the project's services can call each other.

Stop and start it a few times, and run two projects at once if more than one is converted.

### 4. Report

Write the report in your reply to the user, or in a file they name. Include:

- **Each project:** whether portless covers it as is, covers it with changes (list them), or doesn't (list the gaps).
- **Your recommendation:** replace `caddy run` everywhere, in some projects only, or not at all.
- **Machine setup:** whether Caddy's service could be turned back on, and whether the `sysctl` is still needed. portless's `--unprivileged` mode uses it to bind 443 without `sudo`.
- **Clashes with the longer-term plan:** anything that would clash with Caddy listening on the Tailscale address and forwarding to portless. For example, a project that needs ports 80/443 itself, or that must be reachable on the network.
- **Everything you changed,** and how to undo it.
- **Anything you couldn't check.**

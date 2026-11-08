---
name: adding-aspire
description: Use when adding an Aspire AppHost to an existing project, especially a JavaScript or TypeScript repo, so its dev server's logs and traces reach Aspire's dashboard and coding agents can start the server and read its telemetry; or when reviewing such a set-up, e.g. telemetry silently missing, a resource healthy while another process answers its port, or files changing on Windows after `aspire run`.
---

# Adding Aspire to an existing project

Aspire's own skills create and wire the AppHost: `aspire-init` (`aspire init`, the skeleton) and `aspireify` (the resource graph, endpoints, OpenTelemetry).

**REQUIRED:** read and follow `aspire-init` and `aspireify` before creating or wiring the AppHost, including when you're only planning it. For a JavaScript app, read at least `aspireify`'s `references/javascript-apps.md`, `typescript-authoring.md` and `validation.md` as well. If they aren't installed, read them from github.com/microsoft/aspire-skills (`skills/aspire-init/`, `skills/aspireify/`); don't install them. Where they and this skill differ, this skill wins:

- how `aspire init` is run (step 1);
- the app's root `package.json`: leave its `type` and `dev` script alone, rather than adding `"type": "module"` and `"dev": "aspire run"` as `aspireify` suggests, because the nested AppHost package and a root `aspire:start` script (step 2) replace that;
- a fixed port when the dev server's URL must stay the same (step 4), rather than an Aspire-assigned one;
- `addJavaScriptApp` running the project's own `dev` script, rather than a framework-specific resource such as `addNextJsApp`, when that resource's assigned port and arguments would break the fixed URL (step 4);
- the override list (step 3).

Raise `aspireify`'s other optional additions, such as `withBrowserLogs()` (another integration), with the user rather than adding them.

This skill covers what they leave out: keeping a TypeScript AppHost out of a JavaScript app's tooling, the agent side, and the set-up details that make the dev server's telemetry dependable.

Before editing the AppHost, check APIs with `aspire docs search <topic>` and `aspire docs api search <query> --language typescript`. The notes below were checked with Aspire 13.6; recheck any marked *observed* against the current version.

## Order

1. Record a baseline: the app's lint, type-check and test results, before anything changes.
2. Create the AppHost (step 1), then wire it as `aspireify` says, with step 4's details.
3. Keep it separate from the app (step 2), and compare the app's results with the baseline.
4. Commit Aspire's skills and write the agent instructions and project skill (step 3).
5. The user runs the first `aspire run` interactively (the development certificate).
6. Validate as `aspireify`'s `validation.md` says, plus a taken-port check, then stop the AppHost.

## 1. Create the AppHost without the agent set-up

Run `aspire init --language typescript --non-interactive --suppress-agent-init`. An agent may run it: with that flag it leaves the user's agent settings alone. Without `--suppress-agent-init`, init chains the same agent set-up as `aspire agent init`, which writes a hook into the user's **global** Claude Code settings (`~/.claude/settings.json`) as well as installing skills. The skills come in step 3 instead.

In a repo with a root `package.json`, init puts the AppHost in a nested package (`aspire-apphost/`) and points the root `aspire.config.json` at it. Keep that layout.

## 2. Keep the AppHost package separate from the app

- **Own tooling.** The AppHost package has its own `package.json`, lock file, `tsconfig.apphost.json`, and the lint config init creates, if any (don't write one from scratch). Lint and type-check it from its own folder (e.g. `npm --prefix aspire-apphost run lint`, `run build`, whichever scripts init created). Don't fold it into the app's config.
- **Exclude it from the app's tooling.** Add it to the app's `tsconfig.json` `exclude`, the ESLint global `ignores` (a type-aware config fails on its `.mts` files), the test runner if it collects files from it (list what it collects, e.g. `npx vitest list`), and `.dockerignore` (the folder, `aspire.config.json` and `.aspire/`). Check that the app's lint, type-check and tests give the same results as the baseline.
- **Gitignore the generated folders.** Both `aspire-apphost/.aspire/` (the generated SDK) and the root `.aspire/` (the CLI's restore cache). `aspire restore` or the next start rebuilds them.
- **Run `aspire run` directly from the root script, never through `npm --prefix`.** Init writes root scripts such as `"aspire:start": "npm --prefix aspire-apphost run start"`. Replace the one that starts the AppHost with `"aspire:start": "aspire run"`: the CLI finds the AppHost through `aspire.config.json`. Under `npm --prefix … run`, Aspire's own restore of the AppHost's packages added `"aspire-apphost": "file:"` (the package depending on itself) to its `package.json` and lock file on Windows (*observed*; not on Linux). Drop the delegate scripts that only type-check the AppHost unless someone wants them. Say in the AppHost folder's `AGENTS.md` not to commit that entry if it ever appears.

## 3. The agent side

- **Commit Aspire's skills with `aspire:update-aspire-skills`** (REQUIRED SUB-SKILL), not `aspire agent init`. It installs `aspire`, `aspire-orchestration` and `aspire-monitoring` into `.claude/skills/`, unedited, records the version in `.claude/skills/ASPIRE_SKILLS_VERSION`, and keeps the global settings untouched. Nobody else then needs to install them. Document refreshing them after `aspire update`.
- **List where the project overrides Aspire's skills** in its root instructions (`AGENTS.md` or `CLAUDE.md`), under the section about running the AppHost. Aspire's skills give general advice that a project usually doesn't want. Each item says what wins:
  - running `aspire agent init`;
  - adding an MCP server;
  - installing the Aspire CLI or the .NET SDK (a TypeScript AppHost doesn't need .NET);
  - starting in a worktree with `--isolated`;
  - passing `--apphost` when `aspire.config.json` names the only AppHost;
  - leaving a standalone dashboard running and passing `--dashboard-url "…?t=TOKEN"`;
  - moving values from the app's env files (such as `.env.local`) into AppHost parameters, as `aspireify` suggests: when the app loads its own env files and the project forbids reading its secrets files, the app keeps loading them;
  - pointers to skills that aren't installed (e.g. `aspireify`, `aspire-deployment`).
- **Treat the dashboard's login link as a secret.** `aspire start` and `aspire run` print it with its token (`?t=…`). Put this in the instructions: never print, quote or write it down; strip ANSI codes and redact `t=` when quoting Aspire CLI output; pass it through a shell variable if a command needs it. `aspire otel` reads the AppHost's dashboard with no URL. Tell a human user the link is in the command's output rather than repeating it.
- **Say when an agent uses it** in the root instructions. Whenever the agent runs the dev server itself, it starts it under the AppHost rather than with the plain dev script: it's the same server on the same URL. First it checks `aspire --version`. If the CLI isn't installed, it says so and uses the plain script; it never installs the CLI.
- **Write a project skill for running and reading the dev server**, e.g. `running-under-aspire` (provisional name). Its description triggers on running the dev server, reading its console, logs or traces, and its own failure symptoms. Its sections:
  1. **Starting and stopping:** a table of `aspire start --non-interactive`, `aspire wait <resource> --non-interactive` (its default timeout is 120 s, so pass `--timeout <seconds>` if the first compile takes longer), `aspire resource <name> start|stop` for on-demand resources, and `aspire stop --non-interactive` (never `--force`), with this project's resource names and URLs. Tell the agent to stop it when finished, or to say why it's still running.
  2. **What to read:** a table mapping questions to commands (`aspire describe`, `aspire logs <resource>` for the console and compile errors, `aspire otel logs|traces|spans`). Note that `aspire otel` has no metrics command in 13.6, so metrics are read in the dashboard only.
  3. **This project's checks:** e.g. replaying a webhook, then which log or trace shows its effect.
  4. **When something's wrong:** a symptom → cause → fix table (port taken, telemetry stopped, page failing).
  5. **What to take from Aspire's skills,** pointing to the root instructions' override list.
- **Document it for people** in the README (if the project has none, ask where): installing the CLI, the start script, the first-run certificate prompt, the port, and that the login link is private.

## 4. Set-up details for the dev server's resource

Read [references/dev-server-setup.md](references/dev-server-setup.md) before writing the resource: it has an example AppHost and the reasons for each of these.

- **A health route that checks no dependency**, wired with `withHttpHealthCheck`, so `aspire wait` means "answering requests". Don't reuse an existing status route that calls a database or API.
- **`OTEL_LOG_LEVEL=warn`**, so failed exports show in `aspire logs` instead of telemetry silently stopping.
- **`OTEL_EXPORTER_OTLP_CERTIFICATE`** from the AppHost's `NODE_EXTRA_CA_CERTS`, when the dev server replaces that variable with its own certificate authority.
- **A fixed, unproxied port passed to the server** (`env: 'PORT'`) when its URL must stay the same, so a taken port fails rather than moves.
- **`withNpm({ install: false })`** when installing needs credentials or shouldn't run on every start.
- **Telemetry names** that match the resource. If providers are built outside `NodeSDK`, build their resource from the environment too.
- **Structured logs need a log exporter.** Without an OpenTelemetry log exporter, the app's logs reach Aspire only as console output: raise adding one with the user, as it's a new dependency.
- **The development certificate**: the user runs the first `aspire run` interactively.

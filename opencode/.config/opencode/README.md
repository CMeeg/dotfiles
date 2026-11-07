# opencode

## Migrating from OpenCode v1 to v2

Applies when upgrading any machine that runs OpenCode v1 (e.g. 1.18.x). V2 keeps the `opencode` command and shares config locations, but has intentional breaking changes for plugins, the server API, and terminal client config.

This repo's stowed config is already in native V2 shape, so on other machines the migration is mostly: upgrade the binary, restart, restow.

### Steps

1. **Pull this repo** so the stowed config is up to date:

   ```bash
   cd ~/.dotfiles && git pull
   ```

2. **Superpowers** is installed as a plugin from the stowed `opencode.jsonc` (`"plugins": ["superpowers@git+https://github.com/obra/superpowers.git"]`), so there's nothing to update by hand. It needs OpenCode 2.0.4+ and superpowers v6.4.1+ (earlier releases load only on V1). If you still have the old clone at `~/.local/share/opencode/packages/superpowers`, `update.sh` removes it.

3. **Upgrade OpenCode.** V2 installs as `opencode` via the V2 installer and replaces the v1 binary in place (`opencode upgrade` only updates within your current major version, so it won't cross v1→v2):

   ```bash
   curl -fsSL https://opencode.ai/v2/install | bash
   ```

   If v1 was installed via a package manager (apt/npm/brew), remove that installation first so the v2 binary isn't shadowed.

4. **Restart OpenCode.** The v2 terminal client migrates supported global `tui.json` settings to `~/.config/opencode/cli.json` on first start. This repo stows `cli.json` (Dracula) instead of the old `tui.jsonc`:

   ```bash
   cd ~/.dotfiles && stow --adopt --no-folding -v opencode
   ```

   `--adopt` imports the local `cli.json` over the repo file; see `git diff` and commit if V2 wrote anything different.

5. **Verify:**

   - `opencode --version` → 2.x
   - Models and credentials still load (same auth)
   - MCP servers connect: chrome-devtools, microsoft-learn
   - superpowers' skills resolve
   - Ask superpowers: "Tell me about your superpowers"

### herdr integration (V2)

herdr's OpenCode integration supports V1 (≥ 1.18.29) and V2. Older herdr builds (e.g. 0.8.0) ship a V1-only plugin (`plugins/herdr-agent-state.js`, `HERDR_INTEGRATION_VERSION=9`) that does not run in V2. Update herdr and reinstall the integration to get the V2 entrypoint and TUI plugin.

1. **Update herdr:**

   ```bash
   herdr update
   ```

2. **Start the OpenCode v2 TUI once** so the first-start migration runs. If herdr defers registration because V1 TUI preferences are still pending import, start `opencode` once and reinstall the integration afterward.

3. **Reinstall the integration** (overwrites the managed files):

   ```bash
   herdr integration install opencode
   ```

   This installs `~/.config/opencode/plugins/herdr-agent-state.js`, the shared TUI plugin `herdr-tui-session.js`, and the V2 TUI entrypoint `herdr-opencode/tui.js`, and registers the V2 TUI plugin in `cli.json` while preserving existing preferences and plugins.

4. **Review the `cli.json` diff.** `cli.json` is stowed from this repo, so herdr's registration lands in `opencode/.config/opencode/cli.json`. Commit it if herdr is expected on a machine — that makes herdr part of what the stowed `cli.json` requires.

5. **Restart the OpenCode TUI** and verify:

   ```bash
   herdr integration status   # opencode: current (v…)
   ```

   Lifecycle state (`working` / `idle` / `blocked`) then reports from the pane-local TUI. V2 Mini and headless clients do not run the TUI plugin, so they provide no lifecycle reporting.

### Known breakage on V2

- **GitKraken CLI** (`~/.config/opencode/plugins/gk-hooks.js`) is a V1 plugin and does not run in V2. It is vendor-managed and overwritten on update — updating GitKraken is expected to ship a V2-compatible hook plugin. Do not hand-edit.
- **herdr** — supported on V2; see [herdr integration](#herdr-integration-v2).
- `@opencode-ai/plugin@1.16.2` in `~/.config/opencode/package.json` is V1's plugin type package; leave it until a local plugin needs porting to `@opencode/plugin`.

### Rollback

```bash
curl -fsSL https://opencode.ai/install | bash   # reinstalls the V1 binary
```

V1 and V2 share config locations, so only point V1 at pre-conversion config. Back up any project-local `opencode.json(c)` / `.opencode/` files you converted to pure V2 shape before rolling back.

## Known issues

### Superpowers updates don't appear

opencode caches git plugin specs, so a restart may keep serving an older superpowers commit. If an update doesn't show up, clear opencode's package cache or reinstall the plugin (from superpowers' own opencode install notes).

### Git spec plugin install silently fails (V1 only)

This only affected OpenCode 1.17.7, and is why this repo used to clone superpowers instead of using a plugin entry. OpenCode v2 (2.0.4+) installs `git+https://` plugin specs, so the clone is no longer needed.

On 1.17.7, the auto-installer for `git+https://` plugin specs silently failed: it created a cache directory skeleton but never ran its install step, so the plugin never loaded. Adding the git dependency to `~/.config/opencode/package.json` made it worse, because OpenCode then ran a background `npm install` that also failed on the git URL. The workaround was to clone superpowers to `~/.local/share/opencode/packages/superpowers` and point `plugins` at that path, without adding it to `package.json`.

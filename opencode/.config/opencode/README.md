# opencode

## Known issues

### Git spec plugin install silently fails

OpenCode 1.17.7's auto-installer for `git+https://` plugin specs silently fails — it creates a cache directory skeleton but never runs bun install. The plugin never loads. Additionally, if you add the git dependency to `~/.config/opencode/package.json`, OpenCode runs a background `npm install` that also fails on the git URL, compounding the issue.

Solution
Install superpowers outside npm's managed tree and point the config at the path directly:

1. Clone superpowers into a standalone location
   - `git clone https://github.com/obra/superpowers.git ~/.local/share/opencode/packages/superpowers`
2. In opencode.jsonc, use a local path instead of the git URL:
   - `"plugin": ["~/.local/share/opencode/packages/superpowers"]`
3. Don't add superpowers to `~/.config/opencode/package.json`!
   - That would trigger a background npm install that fails.
4. Restart opencode

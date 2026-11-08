---
name: update-aspire-skills
description: Use when a project's committed Aspire agent skills (aspire, aspire-orchestration, aspire-monitoring in .claude/skills/) need adding or refreshing, e.g. after `aspire update` changed the project's Aspire SDK version, or when .claude/skills/ASPIRE_SKILLS_VERSION no longer matches it.
---

# Update Aspire's agent skills

Aspire's CLI generates agent skills (`aspire`, `aspire-orchestration`, `aspire-monitoring`) that a project can commit in `.claude/skills/`, unedited, with the Aspire version they came from in `.claude/skills/ASPIRE_SKILLS_VERSION`. This skill adds or refreshes them with `scripts/update-skills.mjs` in this skill's folder. If the project has its own version of this skill or its own script for it, use that one: it adds the project's specifics to this.

**Never run `aspire agent init` yourself**, in the project or anywhere else: besides the skills, it writes a hook into the user's global Claude Code settings (`~/.claude/settings.json`). The script runs it with its home folder pointed at a temporary one (enough on Linux and macOS), saves the global settings file first and puts it back exactly as it was afterwards (needed on Windows, where the CLI finds the real profile folder anyway), and fails if it can't.

## Steps

1. **Check the versions.** Read `.claude/skills/ASPIRE_SKILLS_VERSION` (absent the first time), the project's Aspire SDK version (`sdk.version` in `aspire.config.json` for a TypeScript AppHost; the `Aspire.AppHost.Sdk` version in a C# AppHost's project file) and `aspire --version`. If `aspire` isn't installed, stop and say so: installing it is the user's choice. If the CLI's version differs from the SDK's, tell the user before going on, since the skills come from the CLI: they may want `aspire update --self` first.
2. **Run** `node <this skill's folder>/scripts/update-skills.mjs` from the project's root. It replaces the three skill folders wholesale and rewrites the version file. If it fails, the skills are left as they were: report its message.
3. **Review the diff** of `.claude/skills/aspire*` and `ASPIRE_SKILLS_VERSION` (`git diff --stat` and `git status --short .claude/skills`, then the changes themselves). Don't edit the skills: an update replaces them, so edits would be lost.
4. **Check the project's overrides still cover them.** Aspire's skills give general advice that a project may not want: running `aspire agent init`, adding an MCP server, installing the CLI or the .NET SDK, starting in a worktree with `--isolated`, passing `--apphost`, leaving a standalone dashboard running, and putting the dashboard's login link (with its `?t=` token) in commands. Find where the project's instructions list its overrides (usually its root `AGENTS.md` or `CLAUDE.md`), look in the new skills for advice of that kind it doesn't cover (commands that install things, change global settings, add an MCP server, or print a token), and propose a change. If the project has no such list, propose one the first time.
5. **Report** to the user: the old and new versions, a summary of what changed in the skills, and any instruction change proposed. Leave the changes unstaged for them to review and commit.

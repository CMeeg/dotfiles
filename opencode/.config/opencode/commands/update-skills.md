---
description: Regenerate the Skill Dispatch table in AGENTS.md from all installed skills
agent: build
---

# update-skills

Regenerate the `## Skill Dispatch` section in `AGENTS.md` by scanning all installed skills.

## Scan these paths

- `.agents/skills/*/SKILL.md` (project-local)
- `.opencode/skills/*/SKILL.md` (project-local alternate)
- `~/.config/opencode/skills/*/SKILL.md` (global config)
- `~/.agents/skills/*/SKILL.md` (global agent-compatible)
- `skills-lock.json` (for remote-installed skills — skip any already covered above)

For each SKILL.md found, read the YAML frontmatter and extract `name` + `description`.

## Generate the dispatch table

Using each skill's name and description, infer what user requests it should trigger on. Produce a `## Skill Dispatch` section like this:

```markdown
## Skill Dispatch

Use the `skill` tool to load the relevant skill when the task matches:

| When the task involves... | Load this skill |
|---|---|
| TypeScript best practices | `typescript-best-practices` |
| Design patterns | `solid-principles`, `gof-patterns`, or `design-principles` |
| Web performance audit or Core Web Vitals | `web-perf` |
```

Cover every skill discovered. Use a concise, readable table format. If multiple skills could apply to the same task, list them all with `or`.

## Update AGENTS.md

1. Read `AGENTS.md`.
2. If a `## Skill Dispatch` section exists, **replace** it entirely with the new one.
3. If none exists, **append** the new section at the end.
4. Preserve everything else in AGENTS.md untouched.

---
name: agent-guidance-retro
description: Use when the user asks to review past sessions or how work with agents has gone, to find recurring corrections, rework or friction, or to propose rules, skills, prompts, settings or AGENTS.md entries that would prevent them.
---

# Agent guidance retrospective

## Overview

Find what the user keeps having to correct, work out why the guidance didn't prevent it, and propose the smallest change in the right place. A correction that recurs although a rule already covers it is a delivery problem, not a missing rule: adding another copy rarely helps.

## 1. Gather the evidence

- **Every message the user typed,** not a keyword search, which misses most corrections: `node <this skill's folder>/scripts/user-messages.mjs --out <scratch>/messages.md` (run from the project folder, which picks its transcripts; `--since YYYY-MM-DD` narrows it). Read it all. Note corrections, repeated instructions, work redone, reversals of the user's own decisions, and approaches they confirmed worked. A long history can be read in batches of sessions (the output has a heading per session; about ten sessions a batch) by subagents, each briefed with the secrets rule and returning themes with counts and short quotes.
- **What agents did that the user never saw:** subagents' transcripts are in `<session id>/subagents/*.jsonl` next to the sessions. Search them, and the sessions' tool calls, for specific risks (e.g. a secrets file's name, `git commit`, a live-system command) rather than reading them whole.
- **The current guidance:** global instructions (`~/.claude/CLAUDE.md`), the repo's root and nested `AGENTS.md`/`CLAUDE.md`, repo and personal skills, other plugins' skills that give defaults (e.g. worktrees, commits, finishing steps), memory, and settings (permissions, hooks).
- Never copy secrets that appear in transcripts into notes or the report.

## 2. Diagnose each theme

Count it and keep one or two short quotes. It's recurring when it comes up in more than one session, or again in the same session after being said; a one-off belongs in the list only if it was costly (work redone, something exposed or broken). Then decide which causes apply (often more than one, e.g. a missing setting and a subagent brief that didn't carry the rule), and propose a fix for each:

| Cause | Fix |
|---|---|
| No guidance exists | write it |
| Guidance exists but is buried in a large file | restructure (`structuring-agent-docs`), don't repeat it |
| It's in a nested file or skill that wasn't loaded | move it to the root, or add a trigger; for a skill, check its description says when to use it |
| Subagents weren't given it | make briefs carry it |
| Another skill or plugin's default contradicts it | say which wins, where the agent will see it |
| Its wording is ambiguous | reword it |
| It lives only in this machine's memory | move it to a file |
| The user's own decisions changed over time | list these separately, neutrally, with a convention for recording reversals |

## 3. Place each suggestion

- **Scope:** every repository → global instructions; this repo → root `AGENTS.md`; one folder → that folder's file; a procedure needed only sometimes → a skill (the user can invoke it, and the agent loads it when its description matches).
- **Existing homes first:** before proposing a new skill or file, check whether one already covers the subject, and extend it.
- **Personal or shared:** the user's own way of working goes in their personal plugins or global file; what the team should follow goes in the repo. For a personal habit that applies to one repo only, ask the user where they keep those, suggesting what the tools they use support (check the docs: e.g. a git-ignored local instructions file in the repo, or a line in their global file naming the repo). Ask whenever it's unclear.
- **Enforcement:** use the platform first (permission rules, sandboxing, settings) before a custom hook or script, and propose enforcement only for what the user wants unbreakable: a deny rule also blocks the user's own in-the-moment request, so it doesn't suit a default the user overrides (e.g. "don't commit unless I ask").

## 4. Present, then wait

A numbered list grouped by theme, each with: what happens and how often, a quote, the cause, the proposed change and its home. Name your top picks. Stop for the user to choose.

## 5. Carry out what's chosen

- Check any claim about how files, skills or settings load against current docs before relying on it.
- Write skills with `superpowers:writing-skills` (a run without the skill first) when it's available.
- Restructure instruction files with `structuring-agent-docs`.
- Record what's deferred in the project's list for it.

## 6. Finish

Ask for a fresh-context review of everything changed (a subagent that hasn't seen the conversation, briefed with the changed files, what they're meant to do and the repository's guardrails, or a code review skill if one is available), check its findings before passing them on, and list what was raised and deferred.

## Common mistakes

- **Searching for keywords** instead of reading the messages.
- **Adding a second copy of a rule** that already exists, instead of finding why it was missed.
- **Enforcing a default** the user sometimes overrides.
- **Building a hook** for something a permission rule or setting already does.
- **Placing a personal preference in a shared repo,** or a team rule in a personal plugin.

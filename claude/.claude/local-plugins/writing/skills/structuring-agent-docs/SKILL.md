---
name: structuring-agent-docs
description: Use when an AGENTS.md or CLAUDE.md file has grown large, after generating one with /init, when adding a section to one and unsure where it belongs, or when moving instructions between root files, nested folder files and skills.
---

# Structuring agent instructions

## Overview

A root instructions file is loaded into every session and every subagent, so each line in it costs context on every task, whether or not the task needs it. Keep in the root what must hold before any action; put the rest where it loads only when it's needed, and leave a pointer behind.

## Measure

- **Measure bytes or tokens, not lines.** Claude Code's guidance is under about 200 lines per file, but a repo that writes each paragraph as one line can be under 200 lines and still 35 KB. 200 lines of ordinary prose is roughly 15 KB (about 4k tokens): treat that as the root's budget, and above it make each section justify being always loaded. A nested file is loaded whole, with its parent folders' files, whenever a file in its folder is read, so the same budget applies to each nested file on its own; what an agent actually gets is that file plus its parents and the root, so keep the chain in mind when a folder is deeply nested: split a large one by subfolder rather than piling more into it. Claude Code also cuts a nested file off past a character limit (40,000 characters with a 200K context window), giving only its start.
- Measure each section at every heading level (e.g. `awk '/^#+ /{if(h)print n, h; h=$0; n=0} {n+=length($0)+1} END{print n, h}' AGENTS.md | sort -rn`) and report the biggest, so the plan targets where the size is. A single long paragraph or bullet counts as one unit there: list its sentences and place each by what it's about, as one bullet often mixes several areas.
- **When the rules that must stay exceed the budget,** shorten them rather than move them: keep the rule in the root and move its rationale, examples and detail to the nested file, skill or README it concerns. Report any overrun that's left, with what it's made of, instead of moving a guardrail out to meet a number.

## Where each kind of text belongs

How files load decides this; check the current docs, as it changes. In Claude Code (as of late 2026): `AGENTS.md` is read only where there's no `CLAUDE.md` (at or above the working directory for the root; in that folder for a nested one); a nested file loads, with the files in the folders above it, when a file in its folder is opened with the Read tool, edited or written, or read whole by `cat` or `head`, but not when a search finds one; subagents load the root file but Explore and Plan agents skip it (so a brief to one of those must carry the guardrails itself); and a skill loads when its description matches the task or someone invokes it.

So place text by the files an agent opens for the tasks that need it, not only by the code it describes. Walk through a few typical tasks: adding a feature opens that feature's own folder, not the shared module it builds on; a config change opens the env files and templates at the root; editing a root-level file (a build, container or server config) loads no nested file at all. When the agents who need a rule work in many folders, or in folders with no instructions file (e.g. one folder per feature), treat it as a cross-folder rule: a short line in the root, with the detail in the file of the module it concerns. Give a folder its own nested file when it has rules or detail of its own, short or long.

| Text | Home |
|---|---|
| Rules that must hold before any action: git, secrets, live systems, who runs what | root |
| Guardrails, including where the repo overrides a third-party skill or tool, and where files go that a tool would otherwise save to its own default place (e.g. a planning skill's specs and plans) | root: a skill or nested file may not be loaded when it matters |
| Rules that apply across folders (e.g. logging, types, comments), including a quirk of a library that any file using it hits (e.g. how every script importing it must run) | root, even if the detail lives elsewhere |
| A map of every nested file, and a one-line trigger for each repo skill | root, once: not a map entry and a pointer bullet for the same file |
| Detail about one folder's code | that folder's `AGENTS.md`, next to the code |
| A procedure followed only sometimes (running a tool, a release step, a checklist) | a skill, with a root line saying when to load it |
| Facts for humans (installing, history, decisions) | README, or the project's decision record |
| Content due to be deleted (e.g. the code and docs of a one-off migration) | wherever it can be deleted with the thing it describes; if part of it is a guardrail (e.g. where a tool must save files), keep that part as a line in the root and move the rest |
| Text that repeats what a skill already says | removed, leaving the one-line trigger for the skill; a guardrail keeps its line in the root even when the skill repeats it |

Writing for several agent tools? Others may not load nested files or skills the same way; keep anything every tool must see in the root.

## Moving text

1. **Save the old copy** before changing anything (`git show HEAD:AGENTS.md > <scratch>/old-AGENTS.md`).
2. **Move verbatim first,** then shorten or reword as a separate step, so each is reviewable. Deleting text because a skill or README already says it belongs to the second step: compare the two first, and move across anything the other copy lacks.
3. **Check nothing was lost or duplicated:** `node <this skill's folder>/scripts/check-moved-text.mjs <old copy> <every new or changed file>`, including the README and skills that received text. Confirm each "not found" line: a paragraph split across files lists any sentence that didn't land; anything else should be a deliberate rewording (its closest match is shown) or a pointer left in its place.
4. **Read each moved piece in its new place.** A sentence lifted from a list or paragraph can lose what it leaned on: an "it", "also" or "see X above" with nothing before it, a possessive standing for a noun ("Telemetry's are …"), a sentence starting lowercase. Fix those, and merge a moved line into one already there that says the same. Text that moved to a document with a different reader (an instructions file's paragraph now in a README for people setting up) is rewritten for that reader in the shortening step: what they should do first, then why, in full sentences, rather than an agent's compressed notes.
5. **Fix what pointed at the moved text:** grep the whole repo, code included (lint messages, scripts, READMEs, skills, open plans), for the old section names and file paths, and the file you split for references to its own sections that have moved out (a `see "Section name"` must now name the file it moved to). Keep a heading's name when other files quote it, or update every quote in the same change. Leave documents that record past work (finished plans, specs, hand-offs already sent) as they are; update open plans and living documents (e.g. a project's decision record or task list).
6. **Update the root's map** for each new nested file or skill. A new skill's `description` says only when to use it.
7. **Ask for a fresh-context review** comparing the old copy with the new files, for meaning changed or lost, broken references, and anything moved where the agents needing it won't load it.

## Common mistakes

- **Counting lines** and calling a 35 KB file small.
- **Moving a guardrail into a skill or nested file,** where it's absent exactly when an agent skips loading it.
- **Moving a cross-folder rule into one folder's file,** so agents working elsewhere never see it, e.g. a library's script quirk filed under the folder that uses the library most.
- **Rewording while moving,** which hides meaning changes in a diff of moved text.
- **Shortening by dropping a reason that stops a mistake** (e.g. "the scripts were removed because…", which tells the next agent not to add them back).
- **Leaving pointers stale** in code, lint messages or other skills.
- **Adding a skill with no trigger in the root,** relying on its description alone for something that matters.

---
name: task-self-review
description: Use when a task, plan step or piece of work is finished and you're about to report it as done or pause for the user's review, before writing the summary.
---

# Task self-review

## Overview

Before handing work over, review it the way the reviewer will, so they spend their review on decisions rather than on catching drift. Fix what you can fix within the task; report everything else. A check counts only with evidence: what you compared, searched or ran, not "yes".

## The checks

Work through every row. Where a row can't apply (e.g. no UI changed), say why in one line rather than leaving it out.

| # | Check | Evidence to give |
|---|---|---|
| 1 | **Placement:** each new or changed module can be described in one sentence without "and"; generic modules hold nothing specific to one product, service or client; each function sits where its subject belongs, not where it was first called | the sentence for each module; any function moved |
| 2 | **Siblings:** new code matches the shape, naming and structure of the existing code that does the same kind of job | which sibling you compared it with, and any deliberate difference |
| 3 | **Idiom:** no framework internals, no unexplained casts, overloads or type-level tricks, no wrapper exposing less than what it wraps, no derived data written onto another API's fields | anything you simplified |
| 4 | **Docs in step:** every document that states something this work changed now says the new thing (README, `AGENTS.md`/`CLAUDE.md`, specs, plans, project notes, comments) | the terms you searched for (old names, paths, behaviours, settings) and the files you updated, or "searched for X, Y: nothing else states them" |
| 5 | **Decisions:** nothing reverses a recorded decision without saying so | the decision record you checked |
| 6 | **Scope raised:** related work you noticed but didn't do (bugs, inconsistencies, better approaches) is either done with the user's agreement or recorded in the project's list for deferred work (with no obvious list, ask the user, suggesting the current plan's addenda, then `PROJECT.md`, then a local `TODO.md`); a change that affects someone else is on the list they read | each item and where it's recorded |
| 7 | **Tests:** each test added or changed guards behaviour someone relies on and would be fixed rather than updated when it fails; scaffolding tests from TDD are deleted or folded into contract-level ones | tests removed or merged, and why the rest stay |
| 8 | **Real run:** a UI, editor flow, integration, script or config change was exercised for real (the app, the command, the build), not only through tests; a visual difference from the reference counts as a regression until the user agrees otherwise | what you ran and what you saw |
| 9 | **Words:** comments say why, in the present tense, with no history or references to plans and tickets; names describe what the thing will permanently be; reusable code names no client, project or local tool; log messages match what's happening | anything you reworded |
| 10 | **Diff hygiene:** each file keeps its line endings (no whole-file rewrites in the diff); no debug output, scratch files or disposable outputs left in the tree | `git diff --stat` checked; anything removed |
| 11 | **Dependencies and config:** every dependency added is flagged; every new or renamed setting reaches each place it must (env files, templates, CI, infrastructure, deployed settings) | the dependency and why; the places checked |
| 12 | **Still running:** processes you started (servers, watchers, containers, browser tabs) are stopped, or reported with the reason they're still up | what's still running and why |

## The report

Add this section to your end-of-task report, before any question to the user:

```markdown
**Self-review**
- Fixed during review: <what the checks caught and you fixed, or "nothing">
- Placement: <one sentence per new or changed module>
- Docs: <searched for …; updated …>
- Scope raised: <item → where recorded, or "none">
- Tests: <kept / removed / merged>
- Real run: <what you ran and saw, or why it doesn't apply>
- Still running: <process and reason, or "nothing">
- Other checks: <any row with something to say; "all clear" otherwise>
```

## Common mistakes

- **Ticking without evidence.** "Docs: checked" tells the reviewer nothing. Name the search terms and the files.
- **Searching only for the new name.** Docs drift through the *old* name, path or behaviour, so search for that.
- **Skipping the docs search because the change is small.** A renamed setting or moved file is exactly what goes stale in a README.
- **Fixing silently.** If the review caught something and you fixed it, say so in "Fixed during review": the reviewer needs to know the first pass missed it.
- **Recording scope in the report only.** A report scrolls away. Put each deferred item in the project's list, and give its location in the report.

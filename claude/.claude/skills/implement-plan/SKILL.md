---
name: implement-plan
description: Use when the user asks to implement (or resume implementing) a written implementation plan. Executes it one task at a time on the current branch, pausing for the user's review after every task, and never stages, commits or pushes.
argument-hint: <path to the plan file>
---

# Implement a plan, one reviewed task at a time

The argument is the plan file to implement. If none is given, ask which plan to use. Don't guess.

## Ground rules

These come from the user and override other skills' defaults, e.g. worktrees, per-task commits, or running all tasks without stopping:

- **Git:** work directly on the current branch. Don't create worktrees or branches, and don't stash, switch or reset. Never run `git add`, `git rm`, `git mv`, `git commit`, `git push` or anything else that stages, commits or publishes. Use plain file operations to create, move and delete files. The user decides what to add, commit and push, and when.
- **One task, then stop:** complete exactly one plan task, then pause for review. Don't start the next task until the user says so. If they ask for changes, make them and pause again.
- **The plan is the authority:** follow its tasks, interfaces and global constraints, and the spec it links to. If something in the plan turns out to be wrong or impossible, stop and raise it. Don't improvise a different design. Small, obvious adjustments (e.g. an API renamed in a newer package version) are fine, but report every one at the pause.
- **Project instructions apply:** follow the repo's `AGENTS.md`/`CLAUDE.md` conventions, e.g. test placement, code style and prose formatting.

## Before the first task in a session

1. Read the plan in full, plus any spec, project overview or earlier plan it references.
2. If `superpowers:executing-plans` is available, load it and follow it, as adjusted by the ground rules above: no worktree, no commits, and pause after every task. Also load `superpowers:test-driven-development` if available. Load whatever other skills the plan names before the steps that need them.
3. Find where to start:
   - the first task with unticked `- [ ]` steps in the plan file; or
   - the task the user names.

   Tell the user which task you're starting.
4. Raise any concerns about the plan before starting, not halfway through a task.

## For each task

1. Work through the task's steps in order, including the failing-test-first steps. Run every verification command the step names, and read its output. Never claim a pass you didn't see.
2. As each step completes, tick its checkbox in the plan file (`- [ ]` → `- [x]`), so progress survives across sessions.
3. Steps that need the user, such as logging in to a service, exporting data, acting in a third-party UI, or confirming a destructive operation, are instructions to them. Give one clear instruction, wait for "done", then verify. Never ask for, or accept, tokens or credentials in chat.
4. Before pausing, load `superpowers:verification-before-completion` if it's available, and re-run the task's final verification commands fresh.

## The pause report

End the turn with:

- **Task N: <name> — done** (or blocked, and why);
- **Changed files:** created, modified and deleted, as clickable paths;
- **Verification:** each command run and its actual result (pass/fail counts, exit codes);
- **Deviations from the plan:** what and why, or "none";
- **Needs your input:** decisions, follow-ups or anything to check in review;
- the question: "Ready for review — shall I move on to Task N+1, or are changes needed?"

## Resuming in a new session

Run `/implement-plan <plan>` again. The ticked checkboxes show where work stopped. Re-read the plan and confirm the next task with the user before starting.

---
name: implement-plan
description: Use when the user asks to implement, or resume implementing, a written implementation plan.
argument-hint: <path to the plan file> [--commit] [--worktree]
---

# Implement a plan, one reviewed task at a time

The argument is the plan file to implement. If none is given, ask which plan to use. Don't guess.

## Choose a mode

Before anything else, run `git worktree list`. If a worktree named after this plan file already exists, an earlier run used it: tell the user, and with their agreement continue in it (see "Resuming in a new session").

Then settle the mode. If the arguments include `--commit` and/or `--worktree`, use those; a flag that isn't passed is off, so don't ask about it. If neither is passed, ask once, with one question offering these four, the first being the default:

| Mode | Where the work happens | Git | When to stop |
|---|---|---|---|
| **In place** (default) | the current branch | nothing staged or committed | after every task |
| **Commit** | the current branch | each clean task committed | only at a task that isn't clean, and at the end |
| **Worktree** | a new worktree on its own branch | nothing staged or committed | after every task |
| **Worktree + commit** | a new worktree on its own branch | each clean task committed | only at a task that isn't clean, and at the end |

A task is **clean** when all of these hold: every verification passed, the self-review left nothing unfixed, its deviations from the plan are none or only the small, obvious kind allowed below, and nothing from it is still awaiting the user (a decision, a question, spotted scope to do now or record). A question the user already answered during the task, or a user step they completed and you verified, doesn't make it unclean.

## Ground rules

These come from the user and override other skills' defaults, e.g. worktrees, per-task commits, or running all tasks without stopping:

- **Git, in every mode:** don't stash, switch, reset, rebase, amend or push, and don't touch any branch except the current one and, in a worktree mode, the worktree's own. Use plain file operations to create, move and delete files.
- **Git, in place and worktree modes:** never run `git add`, `git rm`, `git mv`, `git commit` or anything else that stages or commits. The user decides what to add, commit and push, and when.
- **Git, commit modes:** commit each clean task at step 7 of "For each task". Stage every file the task created, modified or deleted, by path (never `git add -A` or `git add .`), including the plan file and any spec or doc updated under "Keep the plan true". Use the task's suggested commit message, with any attribution lines the harness asks for. Never use `--no-verify`: a failing commit hook makes the task unclean. Never push.
- **The plan's own commit steps:** many plans end a task with a "commit" step. The rules above replace it. In place and worktree modes, skip it and tick it as "(left for the user)". In commit modes, the commit happens at step 7, once the task is known to be clean.
- **Worktree modes:** name the worktree and its branch after the plan file without its extension (e.g. `03-landing-page-and-form`). Create it from the current branch with `git worktree add -b <name> .claude/worktrees/<name> HEAD`, then switch into it with the harness's tool if it has one (e.g. `EnterWorktree` with that `path`); otherwise work there by absolute path. Before creating it:
  - a worktree holds only what's committed, so if the plan file or anything it depends on has uncommitted changes, say so and ask how to proceed;
  - if `git check-ignore .claude/worktrees` says it isn't ignored, ask the user how to ignore it, suggesting `.git/info/exclude`; don't edit or commit `.gitignore` yourself.

  In the worktree, install dependencies with the project's own package manager. Don't copy, read or recreate secret files (e.g. `.env.local`, `.dev.vars`); if setup needs them, give the user one instruction to put them there. Do all the work, including ticking the plan, in the worktree. At the end, leave the worktree and its branch in place and say where they are; merging and removing them is the user's call.
- **Stopping:** in place and worktree modes, complete exactly one task, then pause for review, and don't start the next until the user says so. In commit modes, after committing a clean task, report it in one line (task, commit hash and subject, verification counts, any small adjustment) and start the next task. A task that isn't clean stops the run: give the pause report and leave its changes uncommitted. Once the user approves, commit it and carry on.
- **The plan is the authority:** follow its tasks, interfaces and global constraints, and the spec it links to. If something in the plan turns out to be wrong or impossible, stop and raise it. Don't improvise a different design. Small, obvious adjustments (e.g. an API renamed in a newer package version) are fine, but report every one.
- **Keep the plan true:** whenever a task departs from the plan's text, whether a small adjustment or a deviation the user agreed, correct the plan's text to match what was built. When a task settles an open question in the plan, spec or project doc, mark it answered there. Do both before pausing or committing.
- **Commit messages:** running this skill is the user asking for one. Every task ends with a suggested commit message, even where repo instructions say not to suggest commit messages unless asked. Match the style of the repo's recent `git log`.
- **Project instructions apply:** follow the repo's `AGENTS.md`/`CLAUDE.md` conventions, e.g. test placement, code style and prose formatting.

## Before the first task in a session

1. Read the plan in full, plus any spec, project overview or earlier plan it references.
2. In a commit mode on the current branch, run `git status`. If there are uncommitted changes, list them and ask before starting: a task that has to edit a file which already had the user's uncommitted changes would commit them too, so such a task isn't clean.
3. In a worktree mode, create the worktree now (see the ground rules) and do the project's setup there before running anything.
4. If `superpowers:executing-plans` is available, load it and use its setup, ledger and task loop only. The ground rules replace its "Continuous execution" and "Rulings, not stalls": stop when the mode says to, and raise plan defects rather than ruling on them. "After the last task" below replaces its Final Review and Finish, including `superpowers:finishing-a-development-branch`: don't fix review findings before the user agrees, and don't merge, open a PR, or delete a worktree or branch. Also load `superpowers:test-driven-development` if available. Load whatever other skills the plan names before the steps that need them.
5. Find where to start:
   - the first task with unticked `- [ ]` steps in the plan file; or
   - the task the user names.

   Tell the user the mode and which task you're starting.
6. Raise any concerns about the plan before starting, not halfway through a task.

## For each task

1. Work through the task's steps in order, including the failing-test-first steps. Run every verification command the step names, and read its output. Never claim a pass you didn't see.
2. As each step completes, tick its checkbox in the plan file (`- [ ]` → `- [x]`), so progress survives across sessions.
3. Steps that need the user, such as logging in to a service, exporting data, acting in a third-party UI, or confirming a destructive operation, are instructions to them. Give one clear instruction, wait for "done", then verify. Never ask for, or accept, tokens or credentials in chat.
4. When you notice work the task doesn't cover (a bug, an inconsistency, a better approach), say so and ask whether to do it now or record it; don't broaden the task on your own. Record what's deferred in the project's list for deferred work. If it has none, ask where, suggesting an "Addenda" section at the end of the plan file first. Note each one for the pause report.
5. Before pausing or committing, load `superpowers:verification-before-completion` if it's available, and re-run the task's final verification commands fresh.
6. **REQUIRED:** then use the `task-self-review` skill (`workflow:task-self-review` in Claude Code) and fix what it finds within the task.
7. Bring the plan's text and any open questions up to date (see "Keep the plan true"), then pause or, in a commit mode, commit a clean task.

## The pause report

End the turn with:

- **Task N: <name> — done** (or blocked, and why);
- **Changed files:** created, modified and deleted, as clickable paths;
- **Verification:** each command run and its actual result (pass/fail counts, exit codes);
- **Self-review:** the section the `task-self-review` skill produces, including scope raised and where each item is recorded, and anything still running;
- **Deviations from the plan:** what and why, and where the plan's text was corrected, or "none";
- **Needs your input:** decisions, follow-ups or anything to check in review;
- **Suggested commit message:** in a code block, ready to use;
- the question: "Ready for review — shall I move on to Task N+1, or are changes needed?" (in a commit mode: "Once you approve, I'll commit this and carry on with Task N+1.")

## After the last task

Once the last task is reviewed (in a commit mode, committed), before the plan is called finished:

1. Run a fresh-context review of everything the plan changed: a subagent that hasn't seen the conversation, briefed with the plan, the changed files (in a commit mode, the commits since the run started) and the repository's guardrails. Check each finding yourself, and report those that hold with what you'd fix; fix them once the user agrees, as their own commit in a commit mode.
2. List every item raised and deferred while implementing the plan: from the pause reports, the project's list of deferred work, and `TODO` comments the plan added. For each, say where it's recorded and suggest whether it's worth doing before the next plan starts.
3. Ask the user which to take on now, and record the decision against each item. Nothing is dropped without their say.
4. In a worktree mode, say where the worktree and its branch are.

## Resuming in a new session

Run this skill again with the plan (`/workflow:implement-plan <plan>` in Claude Code). If "Choose a mode" found a worktree named after the plan, switch into it (e.g. `EnterWorktree` with its `path`), read the plan and its ticks from that copy, and continue in the mode the earlier run used, confirming it with the user. Otherwise choose the mode again. The ticked checkboxes show where work stopped. Re-read the plan and confirm the next task with the user before starting.

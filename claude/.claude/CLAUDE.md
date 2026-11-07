# How I like to work

These are my defaults in every repository. A repository's own `AGENTS.md` or `CLAUDE.md` adds to them, and wins where the two disagree; an instruction I give in the moment wins over both.

## Defaults I can override

- **Git:** don't stage, commit, push, stash, switch branches, or `git mv`/`git rm`, unless I ask in the moment. Leave changes in the working tree for me to review and commit, and use plain file operations to move or delete files. When I do ask for git, that covers what I asked for, not the rest of the session.
- **Processes you start:** stop dev servers, containers, watchers and browser tabs once you've finished with them. If there's a reason to leave one running (I'm about to use it, or the next step needs it), say what's still running and why.
- **Steps I run myself:** when something needs me (a login, a command against a live system, a check in a third-party UI), give one clear instruction, then wait for me to say it's done before carrying on. Verify the result afterwards.
- **Dependencies:** I'm not against adding them, but ask first: what it's for, why it beats what's already installed or a few lines of our own, and whether something already planned will replace it. Flag every dependency you add in your summary.

## Scope and follow-ups

- **Say when you spot more scope.** If a task turns up related work (a bug, an inconsistency, a better approach), say so and ask whether to do it now or record it. Never drop it silently, and never broaden the task without asking.
- **Deferrable isn't deferred.** Something stays in scope until I explicitly defer it.
- **One list for deferred work.** Record a deferred item, at the moment it's deferred, in the list the project keeps for them (or a `TODO` comment in the code where it belongs), not scattered across documents. If there's no obvious place, ask where it should go, suggesting in this order: an addenda section in the plan being worked through, the project's `PROJECT.md`, then a local `TODO.md` (which I keep out of git). A change that affects someone else (a client, editors, another team) goes on the list they'll read, without waiting to be asked.
- **Review what was deferred.** At the end of a task, a plan or a sub-project, list what was raised and deferred along the way, so I can decide whether to take any of it on before we move on.
- **Team decisions stay with the team.** Don't hand a client or another team a decision that's ours to make.

## Decisions and names

- **Re-read what's been decided before proposing something.** Check the project's decision record, spec or plan first, and say when a proposal would reverse an earlier decision.
- **When I change my mind, propagate it.** Record the new decision with what it supersedes, then update every document and every piece of code that states the old one, in the same step.
- **Settle names early, and mark what isn't settled.** During design, propose names for the things that will last (modules, types, fields, routes, variables). If I'm not sure yet, mark the name *provisional* in the spec, so renaming it later is expected and done everywhere at once.
- **Name for what something will permanently be,** not for the project, phase or tool that created it.

## Writing code

- **Fit the codebase.** Before writing something new, find the existing code that does the same kind of job and match its shape, naming and structure. If there's a reason to differ, say so.
- **Write code I'd write myself.** Prefer the language's and framework's idioms. Don't rely on a framework's internals, and don't reach for clever type-level tricks, overloads or metaprogramming without asking. If the simple version falls short, explain why before adding the clever one.
- **Place code by what it's about,** not by what first calls it, and keep generic modules free of anything specific to one product, service or client. Each module should be describable in one sentence without "and". Prefer small, focused interfaces over boolean flags that switch a function's behaviour.
- **Wrappers don't offer less than what they wrap.** If you wrap a client or library, expose what it exposes, and put anything you derive in a namespace of your own rather than on the wrapped API's own fields.
- **Write for reuse.** Code, names, comments and docs should be liftable into another project: no client, project or local tool names in anything that could be reused, and anything specific to one project is passed in rather than built in.
- **Fix at the source, but only as wide as the problem.** When a fix exposes an inconsistency in a mechanism, recommend fixing the mechanism where it starts, and name what else that fixes and which callers it touches. When the problem is bad data, fix it where the data is used and only where an issue has been flagged; don't turn a one-off cleanup into a general rule unasked.
- **Avoid churn.** Don't refactor code that's due to be deleted, and don't commit disposable outputs (reports, scratch scripts, generated captures) unless they'll be needed again.
- **Comments say why, in the present tense.** No history ("used to", "as the old system did"), no references to plans, tickets or tasks, and nothing that restates the code.
- **Logs and output tell the truth.** A message shouldn't sound worse (or better) than what's happening, even in a throwaway script, and a runtime message doesn't carry documentation: that belongs in the README or `AGENTS.md`.
- **Use the platform before building on it.** Before writing a hook, script or tool to enforce or automate something, check whether the platform already provides it (permissions, sandboxing, built-in settings), and use that if it fits.
- **Configuration:** trace a new setting through every place it has to reach (local env files, templates, CI, infrastructure, deployed settings), set deployed values explicitly rather than relying on defaults, state units and the reason for any number, and check whether an existing setting already covers it before naming a new one.
- **Scripts:** choose the language for a script by where it will run and how long it will live. A one-off for this machine can be anything; a script others will run, or one that will last, has to run on every OS the team uses (here Windows, macOS and Linux/WSL), so not bash or shell-specific syntax.
- **Line endings:** keep a file's existing line endings when editing it (check with `grep -c $'\r' <file>` first), and watch for tools that silently convert them. New files use LF. In a new repository, suggest a `.gitattributes` that normalises them.

## Verifying

- **Check it in the real app.** Passing tests don't show that a UI, an editor flow or an integration works: run it, including navigation and repeated actions, before saying it's done. A visual difference from the reference (live site, design) is a regression until I've agreed it isn't.
- **Verify claims before relying on them.** A claim about how a library, platform or service behaves, or what the code already does, gets checked against current docs or the code before it goes into a plan, and is marked unverified if it can't be.

## Communicating

- **Explain with examples.** Use a concrete before-and-after when describing a change or a finding, define a term where it first appears, and avoid shorthand I haven't seen. Say which side of a comparison is which. If a design depends on how something behaves at runtime, state that behaviour.
- **Write for the reader.** Work out who will read a document before writing it; leave out what's internal to us, already settled, or not theirs to act on, and avoid wording that implies something unflattering or that could be misread.
- **Prose files:** don't hard-wrap paragraphs or list items in Markdown or other prose; write each as one line and let the editor wrap it.

## Secrets and subagents

- **Never ask for, accept, print or write down a token, key or secret,** and don't read files that hold them (e.g. `.env.local`, `~/.secrets`; a committed `.env` with no secrets is fine). To check a variable is set without showing it, test it (e.g. `[ -n "$(grep '^NAME=' .env.local)" ] && echo set`).
- **A subagent gets the guardrails.** When you brief a subagent, include the rules that keep it safe in this repository (secrets, git, live systems), as it doesn't see this file or the repository's instructions unless you pass them on.

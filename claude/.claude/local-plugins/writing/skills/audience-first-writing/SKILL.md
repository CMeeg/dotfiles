---
name: audience-first-writing
description: Use when writing or revising a document someone other than the user will read or act on, such as a hand-off to another team, a client summary, a status report, a README, release notes, a generated report, or anything shared outside the conversation.
---

# Audience-first writing

## Overview

Decide who reads it and what they'll do with it before writing a word. Most rewrites of shared documents come from writing for ourselves: internal detail the reader can't use, things they've already settled, wording that implies something we didn't mean, or a report that says what's wrong but not what to do.

## Before drafting

Answer these, and show the answers to the user with the draft (they aren't part of the document):

1. **Who reads it?** Name the reader: a client's editors, another team, a developer new to the codebase, a future maintainer. If there are several, who comes first?
2. **What will they do with it?** Decide, approve, act on a task, set something up, look something up later.
3. **What's its purpose and lifetime?** e.g. "these tests stay after the project ends" changes how you frame them.
4. **What do they already know or have settled?** Leave that out.

## Writing it

- **Lead with what the reader needs to do or decide,** then the detail behind it.
- **Only what's theirs.** Leave out our internal process, tooling and history, anything already handled, and decisions that are ours to make rather than theirs.
- **Facts are checked, or worded only as far as they're known.** Don't invent a team, a role or a process; ask. For a claim you couldn't verify, write what you know (e.g. "the floor area reaches the website without its unit") rather than a guess at the cause ("the supplier doesn't send a unit").
- **Words that can't be misread.** Prefer the precise term to the friendly one when the friendly one has another meaning (e.g. "URL", not "web address", which reads as a postal address). Define a term where it first appears. Avoid words that suggest the wrong state (e.g. "placeholder" suggests unfinished).
- **No unintended implications.** Read each claim as the reader will: "access is now locked down" implies it wasn't before. Say what's true now without implying a past failing, unless that's the point.
- **Depth matches the reader.** Start with the basics; put caveats and edge cases in sections of their own. Too much detail reads as a problem, or hides the part that matters.
- **Images and comparisons say which is which** (e.g. "live on the left, the new build on the right").

## Reports and generated output

- Every section or category says what it means and what the reader should do about it. A category with no explanation leaves the reader unable to act.
- The summary matches the body: every category in the body appears in the summary, with the same counts.
- Messages and statuses don't sound worse, or better, than the reality.

## Before sending

Re-read the draft as the reader, once, against this:

| Check | Fix |
|---|---|
| Anything they can't act on or didn't need? | cut it |
| Anything they've already settled? | cut it |
| A term they might misread? | the precise term, or define it |
| A sentence that implies a past failing or a state that isn't true? | reword it |
| A section with no "so what"? | add what to do, or cut it |
| Summary and body disagree? | make them match |

## Common mistakes

- **Writing the reader brief in your head only.** Show it to the user: a wrong guess about the reader is the most expensive mistake to fix later.
- **Framing by our project's goal** rather than the reader's (e.g. "migration regressions" for tests that outlive the migration).
- **Handing over our decisions.** If the team can decide it, decide it, and tell the reader the outcome only if it affects them.

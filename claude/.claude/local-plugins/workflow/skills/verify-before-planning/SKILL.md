---
name: verify-before-planning
description: Use when writing or revising a spec, design or implementation plan, or proposing an approach, that rests on how existing code, data, libraries, platforms or services behave, or on what has already been built or decided.
---

# Verify before planning

## Overview

A plan is only as good as the facts under it. Every claim a plan relies on is either checked, with a note of how, or marked unverified with how it will be checked and what changes if it's wrong. A wrong fact found in review costs a revised plan; found while implementing, it costs rework.

## What counts as a claim

Anything the plan would be wrong without:

- **The code:** what a module does, what exists already, what was built in earlier work, what a function's callers are
- **The data:** which values occur, how much there is, what's missing or malformed
- **Libraries:** the current version, an API's shape or behaviour, a default
- **Platforms and services:** what a host, CDN, proxy, cloud service or third-party API does (headers forwarded, timeouts, limits, caching)
- **Configuration:** which settings exist, their values per environment
- **Decisions:** what the project has already decided, and what a proposal would reverse
- **Numbers:** a timeout, limit, size or interval the plan chooses

## How to check

| Claim about | Check it by |
|---|---|
| Code, config, what exists | reading it (search for every caller and every place a setting is used); for "was this done already?", the code and the project's status docs, not memory |
| Data | querying it read-only, or asking the user to run the query |
| Libraries | the registry for the latest version (e.g. `npm view <pkg> version`), then current docs (a docs skill or tool such as `find-docs` or Context7 if available) for the version you'll use |
| Platforms and services | official docs; where they're silent, a small experiment, or mark it unverified |
| Decisions | the project's decision record, `PROJECT.md`, spec and earlier plans |
| Numbers | the reason, written next to the number, with its unit; a measurement where one is possible |

Before designing something new, check what's already available: installed skills, plugins and MCP tools, the library's own features, and existing code that does the job.

## Spikes and measurements

- **Measure before deciding** when the choice turns on cost, size or speed. Write the measurement into the spec, not a guess.
- **Test the obvious second case.** If a spike proves "uploading a new X works", also prove "replacing an existing X works", or whatever the realistic neighbouring case is. Spikes against a live system cost the user's time and the system's state, so cover both cases in one run.
- **Keep the detail proportional to the certainty.** Where an area is uncertain, the plan sets constraints and the check to run, rather than prescribing code that the check might invalidate.

## The Basis section

Every spec and plan ends with this section (a plan whose spec already has one lists only its new claims):

```markdown
## Basis

| Claim | Status | How |
|---|---|---|
| `formatPrice` is only called from `PropertyCard` | Verified | searched for `formatPrice(`: 1 caller |
| Supabase `floor_area_unit` holds only `sq ft` and `sq m` | Unverified | needs a query against the live database; if other values occur, Task 2 maps them to "unknown" |
| Reverses decision 4 (stories own their slugs) | Flagged | user to confirm |
```

Statuses: **Verified** (with what you read, ran or measured), **Unverified** (with how it will be checked, by whom, and what changes if it's wrong), **Flagged** (a decision for the user).

## Common mistakes

- **Answering from memory.** Training data is out of date for versions, APIs and platform behaviour. Check.
- **"The code does X" from reading one call site.** Search for every caller before claiming a behaviour or proposing a change to it.
- **Assuming earlier work happened.** "This was migrated in slice 3" gets checked against the code, not recalled.
- **Unverified claims dressed as verified.** If you inferred it, say inferred, and say from what.
- **"The code already does it" as proof.** Existing code shows what the code does, not that it's right: a standard's codes, a platform's behaviour or a library's contract are checked against their own docs.
- **A number with no reason.** "Timeout: 30s" invites "why 30?". Give the reason and the unit.

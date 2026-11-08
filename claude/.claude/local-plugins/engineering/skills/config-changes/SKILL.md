---
name: config-changes
description: Use when adding, renaming, removing or changing the default of an environment variable, app setting, secret, feature flag or config file entry, or when code starts reading a setting it didn't read before.
---

# Config changes

## Overview

A setting has to reach every place that runs the code: local env files, templates, CI, infrastructure, and each deployed environment's settings. The usual failure is a setting that works locally and is missing, or literally unset, everywhere else. The reliable map of where a setting must go is an existing setting that already gets there.

If the project has its own version of this skill, use that one: it adds the project's specifics to this.

## Before adding one

- **Does a setting already cover it?** Search the existing names and their docs. Reuse beats a second name for the same thing (e.g. one shared secret rather than a copy with a new name).
- **Name it like its siblings:** same prefix, case and style as the settings around it.
- **Decide its shape:** required or optional; its default and why; the unit for a number (ms, s, KB) in its name or comment; secret or not; whether it's needed at build time, at runtime, or both; and whether it can be optional only in local development.

## Trace it through a sibling

1. Pick an existing setting that's most like the new one: same kind (secret or not), same phase (build or runtime), read the same way.
2. Search the whole repository for the sibling's name, including dotfiles, templates, CI and infrastructure folders (e.g. `git grep -n SIBLING_NAME`, or a search that doesn't skip hidden files).
3. Each hit is a place the new setting probably needs too. Add it to each, in the same form, or note why it doesn't apply.
4. List what lives outside the repository, which the sibling's hits point to but you can't change (e.g. pipeline variables, a vault, a cloud console's app settings). These are the user's to create, per environment.

## In the project

Find these before tracing; the project's instructions, README and an existing setting's search hits usually show them, and check your trace against them:

- **The places a deployed setting must reach:** a template the build checks, CI steps that pass variables on, infrastructure parameters, and per-environment values someone creates by hand.
- **What a missing value looks like in each:** empty, absent, or a placeholder the pipeline leaves in (e.g. Azure Pipelines passes an undefined `$(NAME)` through as that text), and how the project's config helpers treat it.
- **Where values go:** committed files for non-secret values that are the same everywhere, an ignored local file or a vault for secrets.
- **Who creates what the repository can't change,** so the hand-over names it.
- **How environments are told apart:** separate deploy jobs or stages, per-environment variable groups or files. If the deploy has only one environment but the setting must vary, say what giving each environment its own value would take, rather than adding it unasked.
## Rules

- **Set deployed values explicitly.** Don't rely on a default for a deployed environment; give each environment its value, even an empty one, so what runs is what's written down.
- **Keep the plumbing when a value is blanked.** Turning a feature off by blanking its value shouldn't remove it from templates and pipelines, so turning it back on is one change.
- **Know what "missing" looks like in each place.** Some pipelines pass an undefined variable through as literal text (Azure Pipelines' `$(NAME)`), others as an empty string (GitHub Actions' `${{ vars.NAME }}`), and an empty value passed on can override a default further along (e.g. Helm's `--set` over `values.yaml`). Read settings through the project's config helpers where they exist, and check how they treat that case.
- **Validate at startup.** A required setting that's missing or invalid stops the app at startup, with a message naming it, rather than failing on first use.
- **Never write a secret's value** anywhere: not in a committed file, a test, a log, a plan or a message. Check a secret is set without printing it.
- **Document it where its siblings are documented** (a template's comment, the README, `AGENTS.md`): what it's for, whether it's optional, its default and its unit.

## Report

```markdown
**Config trace: `NEW_SETTING`** (traced through `SIBLING_SETTING`)
| Place | Status |
|---|---|
| `<env template or example file>` | added, with comment |
| `<CI or deploy step>` | added |
| `<infrastructure or chart values>` | added |
| `<value set outside the repository>`, per environment | **for you to create:** `<each environment>` |
```

## Common mistakes

- **Stopping at the local env file.** Works on your machine, missing in every deployed environment.
- **Tracing from memory** instead of searching for a sibling's name.
- **A new name for an existing value,** which then has two copies to rotate.
- **A number without a unit or a reason,** e.g. `TIMEOUT=30` (seconds? milliseconds? why 30?).

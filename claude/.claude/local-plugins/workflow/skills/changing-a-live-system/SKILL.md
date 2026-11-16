---
name: changing-a-live-system
description: Use when a task changes a running system rather than files in a repo, such as installing or removing software, services, certificates, firewall or network settings, containers and their data, a database, credentials, or settings in a cloud account or third-party dashboard (Cloudflare, Tailscale, GitHub, DNS), including setting up or rebuilding a machine.
---

# Changing a live system with its owner

A live system's changes reach other software, other people and data that may not come back, so the owner stays in charge of each one: you take stock, propose each change with its undo, prepare what they run, and check the result. The global instructions' **Steps I run myself** rules apply throughout; this skill is how to carry a whole job through with them.

## Take stock first

Before changing anything, list the read-only checks you'll run (what's already there and what would clash: other copies of the software on `PATH`, ports already taken, old config, data or certificates, an earlier attempt's leftovers), and run them once the owner approves the list. Ask the owner about what only they can see: dashboards, other devices, what still uses an old credential. Record what you find as "already present".

## Who does what

| The owner | You |
|---|---|
| Commands that need administrator rights or `sudo`, including installs that raise a UAC prompt, and restarting the machine | Read-only checks, from an approved list |
| Changes in a cloud account, third-party dashboard or app's settings | Commands without admin rights that change only what an approved change list names on this machine, are not destructive, and can be undone (e.g. creating a local container, even an empty database one, which holds no data yet, so it isn't a change in a database; a user-level config file) |
| Anything touching data in a database, shared environments (staging, a team's account; whether to change them may also be the team's call) and credentials | Instructions, scripts and commands you prepare for the owner, documented as the global rules say |
| Anything destructive or that can't be undone, by hand or from a script they asked you for | |

Their steps stay theirs even when they offer to hand them over.

## Each step

1. **Change list:** each change, who makes it, and its undo, or that it can't be undone. Wait for approval.
2. **Their part:** one instruction, wait for "done".
3. **Check** the result yourself; say plainly what you didn't see.
4. **Record** it (below).

## What can't be undone

Say so in the change list, and in what you give the owner. Prepare a script or command for it only when they ask, documented in full. Where data would be lost, suggest a backup first (e.g. dump a database or a container's volume before deleting it): the deletion after it is still the owner's, as the backup may not cover everything. Removing a container while keeping its volume is the undoable version.

## Recording

- **A change list for the job:** every change with its undo, written as it happens. If a plan is being followed, it goes there; otherwise ask where, suggesting a plan with **Decisions**, **Changes on this machine** (change, undo) and **Addenda** sections.
- **Things that matter later:** an expiry date, a request waiting on someone else, anything left running on purpose.
- **Docs that describe the set-up:** where reality differed, fix them.

## Secrets

- A credential pasted into the chat is exposed: don't use it. Have it replaced, and the new one saved by the owner straight into its file. Replacing it revokes the old one, which can't be undone if something else still uses it, so ask what does first.
- Check a secrets file by its existence and size, never its contents. One you can't read (admin-only) is checked by the owner, or by its effect (the service that uses it works).

## While the owner is away

Do the approved read-only checks and prepare their steps, then give them one numbered list of what you need, each with its one-line instruction. This is the one exception to giving one instruction at a time: nothing on it moves until they say it's done.

## Finishing

Stop what you started (servers, tunnels, browser tabs) and say what's still running and why. For a machine's set-up, a restart and a second check show what comes back by itself.

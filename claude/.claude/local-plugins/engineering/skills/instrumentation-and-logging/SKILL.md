---
name: instrumentation-and-logging
description: Use when adding, changing or reviewing log statements, log levels, error reporting, traces, spans, metrics or telemetry set-up (OpenTelemetry, exporters, sampling, health checks), or when deciding how a failure should be reported.
---

# Instrumentation and logging

## Overview

Logs and telemetry exist so someone can diagnose a problem in an environment they can't attach a debugger to. Every line logged outside development is usually paid for (hosted logging charges by volume) and read by a person, so each one should help answer "what happened and why", at a level that matches how much it matters, without noise, duplicates or secrets.

If the project has its own version of this skill, use that one, as it adds the project's specifics to this, and still follow this skill's "In the project" pointers to tool references.

## Choosing a level

| Level | When | Example |
|---|---|---|
| `fatal` | the app can't carry on | required configuration missing at startup |
| `error` | something failed that shouldn't have | a call failing after its retries; an unexpected exception |
| `warning` | something went wrong or looks wrong, but was handled | content that doesn't match its schema; two pages claiming one URL |
| `info` | worth seeing while developing, or while monitoring with the level turned up | startup steps; a webhook's summary |
| `debug` | diagnostics | cache hits and misses; what a call returned |
| `trace` | very fine-grained, for chasing one problem | each item of a loop |

Two rules decide most cases:

- **Who can cause it?** Anything a member of the public can trigger at will (a bad form post, a made-up ID, a bot) is `info` or `debug`, never `warning` or `error`, or anyone can fill the paid-for logs. But separate it from a problem the team can fix that shows up on the same path (e.g. a real record missing a required field): that one is a `warning`, logged on its own branch, so it's seen by default.
- **When a team-fixable fault looks like public noise** (a wrong signing secret also produces "bad signature" requests, which bots send too), keep the line at `debug` and make a sudden run of them visible another way: a metric or counter that can alert, or a `warning` only when every request fails for a while.
- **Expected outcomes aren't failures.** A 404, a request the caller aborted, or a cache miss is `debug`.

## Writing a log line

- **Use the logger's own form.** Follow how the project's existing log calls pass values and errors; if nothing calls the logger yet, follow its library's documented form (e.g. pino takes the properties object first and expects an error under `err`; LogTape takes a message with `{placeholders}` filled from the properties that follow).
- **Values as properties, not in the message:** `logger.warn({ slug }, 'Story is invalid')` or `logger.warn('Story {slug} is invalid', { slug })`, whichever the logger's form is. Properties stay searchable and the message stays constant, so identical events group together.
- **Pass the error object itself,** under the key the logger expects (`err`, `error`), not `error.message`, so exporters record the exception's type and stack.
- **Summaries carry the detail as properties:** a summary of work done (e.g. what a webhook invalidated) lists what it touched, not only counts, so its effect can be read back later.
- **Log once, at the layer that knows.** If a lower layer (a client, a fetch layer, the framework) already logs a failure, the caller doesn't log it again; it adds context only if it has some the lower layer lacks. Check the framework too: some print an error and pass it to a hook as well.
- **Messages tell the truth:** not more alarming than what's happening (a planned deletion isn't "Deleting!!"), and not less.
- **No secrets or personal data:** never log a token, key, password or a URL that holds one (redact it first, e.g. a URL's query string), nor a person's name, email, phone number or address; log an ID that leads to them instead.
- **No documentation in messages:** how to use a tool or set something up belongs in the README or `AGENTS.md`, not in a log line, and neither names a particular developer's tooling.

## Telemetry set-up

- **Honour the standard variables** (`OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_RESOURCE_ATTRIBUTES`, `OTEL_METRIC_EXPORT_INTERVAL`, `OTEL_LOG_LEVEL`) rather than hard-coding what they control, and keep the app's own log level separate from the SDK's diagnostic level.
- **One resource for traces, metrics and logs,** merged from the same detectors, so they line up in the backend.
- **The same sampler everywhere,** with only the ratio differing by environment, so local runs behave as deployed ones do.
- **Make export failures visible:** with no diagnostic logger, a failing exporter is silent.
- **Look meters and counters up when they're used,** not once when a module loads or first uses them: a meter created before the SDK starts can stay a no-op for the life of the process, and in tests one created once stays bound to the first test's provider.
- **Flush on shutdown yourself** (e.g. on `SIGTERM`) rather than relying on a framework to call a shutdown function it may discard, and check the framework's own signal handling doesn't exit before the flush finishes: a listener of your own runs beside it, not before it.
- **Filter noise at the source:** health-check polls and framework-internal spans can be dropped by route or span type; keep health checks free of dependency checks, so an outage elsewhere doesn't get a healthy app restarted.
- **Log that guards and handlers are registered** at startup (one line), so their presence can be confirmed in production.

## In the project

**If the project logs through LogTape, or sets up OpenTelemetry's Node SDK,** load the `typescript:typescript-best-practices` skill and read its `references/logtape.md` or `references/opentelemetry.md` (or both) before writing any code: each applies this skill with that tool.

**If the project is a Next.js app,** load the `nextjs:nextjs-instrumentation` skill as well: it covers starting logging and telemetry from `instrumentation.ts`, and what Next already does around them.

Find these before adding logs or telemetry; the project's instructions and its existing logging usually show them:

- **The logger** and how a module gets one (never `console` where the project has a logger), and its message syntax: placeholders filled from properties, or something else.
- **The default levels** in each environment, what overrides them, and whether logs outside development are paid for, which sets how much `info` is acceptable.
- **What already logs** (a fetch layer, an error boundary, a loader helper), so callers don't log the same failure again.
- **Where telemetry is set up** (exporters, sampling, filters) and how to read it while developing (a local dashboard or CLI).
- **How tests assert logs,** if they do.
## Common mistakes

- **`warning` for something anyone can trigger,** filling the paid-for logs.
- **Logging a failure twice:** once where it happens and again in the caller.
- **`error.message` instead of the error,** losing the type and stack.
- **Building the message from values,** which breaks grouping and search.
- **Logging counts without the lists** they summarise.

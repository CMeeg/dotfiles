---
name: nextjs-instrumentation
description: Use when setting up or changing a Next.js app's instrumentation.ts (register, onRequestError), or its logging, OpenTelemetry, process guards or health check; or when telemetry is lost on shutdown, a failed request is logged twice or without its stack, fetch calls are missing from traces or traced twice, or the edge build fails with "Module not found: Can't resolve" a Node module.
---

# Next.js instrumentation

## Overview

`instrumentation.ts` (at the project root, or in `src/`) is a Next.js server's start-up hook: Next calls its `register()` once in each runtime a server starts (Node.js, and the edge runtime when anything runs there), and its `onRequestError()` for every request that fails on the server. That's where logging, telemetry and process guards start. Most of what goes wrong there comes from what Next already does around these hooks, so this skill is about that, for the Pages Router and the App Router.

This skill adds the Next.js part to three others; load them too:

- `engineering:instrumentation-and-logging`: what to log, at which level, and the telemetry set-up rules.
- `typescript:typescript-best-practices`, `references/opentelemetry.md` (the Node SDK) and `references/logtape.md` (if the app logs with LogTape).
- `nextjs:nextjs-module-state`: shared instances and once-guards, which logging and the console bridge need.

Next and OpenTelemetry's JavaScript packages both change between versions, so check what the installed versions do: their docs (e.g. through Context7), their types and, for Next's behaviour the docs don't cover, its source in `node_modules/next/dist/server/`. The behaviour here was checked in running apps on Next 15.5 and 16.4 (Pages Router, App Router, and both together; Turbopack, and webpack for the edge build) with `@opentelemetry/sdk-node` 0.301, and against their source; where the versions differ, the references say so.

## Layout

Keep `instrumentation.ts` thin and give each job its own module. Match the project's names and folders; these are the jobs:

| Module | Job |
|---|---|
| `instrumentation.ts` | `register()` and `onRequestError()` only. Its top-level imports must run on the edge too |
| telemetry | starts the Node SDK; returns the logger provider and a `shutdown()` |
| logging | configures the logger once; `getAppLogger(area)`. The module `instrumentation.ts` imports at the top is edge-safe |
| flush | the logger's and the SDK's shutdown, in order, run once, for the signal handler and the guards |
| console bridge (optional) | sends `console` output (Next's, libraries') to telemetry. Its error marker for `onRequestError` is in a module of its own that imports nothing, as the edge build imports it too |
| process guards | decide when an unhandled rejection or uncaught exception should end the process |
| span filter | an exporter wrapper that drops Next's noisy span types |
| health route | answers 200 and checks nothing else |

## `register()`

| Rule | Why |
|---|---|
| **Put Node-only work inside a literal `if (process.env.NEXT_RUNTIME === 'nodejs') { … }` block, and import its modules there with `await import()`.** Not an early return (`if (process.env.NEXT_RUNTIME !== 'nodejs') return`), and not the value copied into a variable | when anything runs on the edge (an edge route, or `middleware.ts`, which is deprecated in 16 but still runs there), Next compiles the file for the edge runtime too, replacing `process.env.NEXT_RUNTIME` with that runtime's name. Under webpack (Next 15, or 16 with `--webpack`) an early return leaves the imports in the edge build, which fails with `Module not found: Can't resolve 'stream'` (or `fs`, `net`, `tls`, `zlib`); Turbopack (16's default) drops them but warns that a Node.js API is used. The literal block builds cleanly under both. Next 16's `proxy` always runs in Node |
| **Start telemetry first,** then logging (it needs the SDK's logger provider), then the process guards, then any fail-fast configuration checks | logs can only go to telemetry once it has started; a configuration check that throws here stops the server starting, rather than failing its first request |
| **A flag turns telemetry on or off, and nothing else.** Logging, the guards and the checks always run | turning telemetry off mustn't also turn off the crash protection or the log output |
| **Log one line once the guards are registered** | so their presence can be confirmed in production |
| **Keep the state the steps share behind a once-guard on `globalThis`** (`nextjs:nextjs-module-state`), e.g. the logging configuration | Next runs `register()` once per server process (15.5 and 16.4), but the modules it calls are also imported by routes, each bundled separately, and the development server re-runs those when it recompiles |
| **Restart `next dev` after changing `instrumentation.ts` or a module it imports** | the development server doesn't run `register()` again, and keeps the old `onRequestError`, until it restarts (16.4) |
| **A logger that its own instrumentation patches** (pino, winston, bunyan) **is imported after `sdk.start()`,** inside the block, and kept out of the bundle (check `serverExternalPackages`; Next lists pino by default) | it's patched as it loads, so one loaded before the SDK starts, or bundled, sends no records to telemetry and carries no trace IDs |
| **If an edge route or edge middleware logs,** configure logging in the edge runtime too, in an `else if (process.env.NEXT_RUNTIME === 'edge')` block, with a console sink only | otherwise their records go nowhere, and only Next's printing of a failure is left |

## The rest, by task

| Task | Read |
|---|---|
| Flushing telemetry when the server stops: why a `SIGTERM` listener loses the race, and `NEXT_MANUAL_SIG_HANDLE` | `references/shutdown.md` |
| Logging a failed request from `onRequestError()`, and sending Next's console output to telemetry without logging it twice | `references/request-errors.md` |
| Ending the process on an uncaught exception or too many rejections, given that Next already catches both | `references/process-guards.md` |
| Next's own spans, the `http` and `undici` instrumentations by router, bundled packages, noisy spans and dropped spans, `@vercel/otel` | `references/tracing.md` |
| A starting version of each module in the layout, for both routers | `references/examples.md` |

## Health check

- **One route that answers 200 with `Cache-Control: no-store` and checks nothing else** (`pages/api/health.ts`, or `app/api/health/route.ts`), so an outage elsewhere doesn't get a healthy server restarted.
- **In the App Router, make it dynamic with `await connection()`** (from `next/server`). With `cacheComponents` on, a constant response is prerendered at build time, and `export const dynamic = 'force-dynamic'` fails the build.
- **Keep middleware (`proxy` from Next 16) off it** with the matcher, if middleware calls anything that can fail.
- **Its polls make traces:** if the platform polls often, drop them in the sampler (Next's root span carries `http.target` when it starts, so the whole trace is dropped; compare its path without the query, which it includes) or the span filter. A custom sampler is replaced when `OTEL_TRACES_SAMPLER` is set, so the polls come back then.

## Common mistakes

- **An early return on the runtime** instead of the literal block, so the edge build tries to bundle the SDK.
- **Returning a shutdown function from `register()`,** which Next never calls, or trusting a `SIGTERM` listener to win the race against Next's exit.
- **`ignoreIncomingRequestHook: () => true`** on the `http` instrumentation, which stops every span in the request, Next's included.
- **Gating the guards or logging on the telemetry flag.**
- **Exiting from a guard with nothing to restart the process.**
- **A patched logger (pino, winston) imported at the top of `instrumentation.ts`,** before the SDK starts and in the edge build.
- **Writing guards as if Node would crash on a rejection,** and logging every rejection that Next already prints.
- **Logging `error.message`,** wrapping an edge route's error in `new Error(String(error))`, or logging the request's headers or query.
- **`fetch` traced twice** (the App Router, or any route once an App Router page has loaded), or the Pages Router's not at all because `undici` was turned off.
- **A console bridge without de-duplication,** so each failed request reaches telemetry three or four times.

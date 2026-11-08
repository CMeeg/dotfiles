# Failed requests and console output

Part of the `nextjs-instrumentation` skill: logging a failed request from `onRequestError()`, and sending Next's own console output to telemetry without logging that failure twice.

## `onRequestError()`

| Rule | Why |
|---|---|
| **Log the error itself, as a property,** not `error.message` in the text. Turn anything that isn't an `Error` of this realm into one, keeping its `name`, `message` and `stack` (`toError` in `examples.md`) | the exporter turns an `Error` into `exception.type`, `exception.message` and `exception.stacktrace`, so the backend shows an exception rather than a message. An edge route's failure reaches the Node runtime's `onRequestError` as an error from another realm, which fails `instanceof Error`; `new Error(String(error))` would replace its stack with `onRequestError`'s own |
| **Add the request's `method` and `path`, and the context's `routerKind`, `routePath` and `routeType`,** plus `renderSource`, `revalidateReason` and `renderType` where they're set (the App Router) | they say which route failed and how it was rendered |
| **Leave out `request.headers`,** and strip the query from `path` | headers hold cookies and authorisation; `path` includes the query string, which can carry a token |
| **Keep it edge-safe:** import only edge-safe modules at the top of `instrumentation.ts`; a Node-only logger is imported with `await import()` inside a literal `if (process.env.NEXT_RUNTIME === 'nodejs')` block in `onRequestError` too (Next's docs show the pattern for `register`; it works in both hooks) | the file is compiled for the edge when anything runs there |
| **Don't filter `notFound()` or `redirect()` by `digest`** | Next doesn't call `onRequestError` for them (15.5 and 16.4): an App Router render skips its control-flow errors, and the Pages Router returns them rather than throwing |
| **Catch and log in `proxy` yourself** (Next 16) | a Node-runtime `proxy` that throws didn't reach `onRequestError` in 16.4, in production or development, although the docs list `routeType: 'proxy'`; check the installed version before relying on it |
| **Don't log the same failure again** in the route or page that threw it, unless the route adds context `onRequestError` lacks | it's already logged here |

**Next prints the error too** (through its own logger, which writes to `console.error`, mostly prefixed ` ⨯`), so every failed request appears more than once in the console: Next's text and your structured record. When it prints, relative to calling `onRequestError`, depends on the kind of route and the version:

| Failure | 15.5 | 16.4 |
|---|---|---|
| Pages Router page (`getServerSideProps`, render) | before, then again after from a copy with the same stack | before, then again after (a render error also once more as a plain `Error:` first) |
| Pages Router API route | after, then again | once, after |
| Edge API route | not checked | twice, after |
| App Router server component | not checked | once, before |
| App Router route handler | not checked | once, before |

That's harmless in the console, but a console bridge would send each one to telemetry as well: see "Console output".

## Console output

Next and many libraries write straight to `console`, which never reaches telemetry. If it should (where else would Next's own errors show?), bridge it: wrap `console`'s methods so each call also emits an OpenTelemetry log record.

- **Only at or above the app's log level,** with a list of patterns to ignore for known noise.
- **Render an `Error` with its stack;** `JSON.stringify` gives `{}`.
- **Give the logging library's console sink the console from before bridging,** or every record the app logs is sent twice.
- **Leave out errors `onRequestError` has logged:** it marks each error (the object, and its stack in a small bounded set, both on `globalThis`); the bridge holds console output carrying an `Error` for a second, keeping its timestamp and trace context, and sends it only if that error wasn't marked. The second covers Next printing before it calls `onRequestError`; matching the stack covers a copy. In both versions' tests this left none of the prints above in telemetry.
- **Recognise an error by shape, not `instanceof`,** in the bridge too: an edge route's error comes from another realm.

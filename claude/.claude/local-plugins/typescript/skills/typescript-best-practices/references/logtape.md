# LogTape

How to apply the `instrumentation-and-logging` and `writing-tests` skills in a project that logs through [LogTape](https://logtape.org) (`@logtape/logtape`). Those skills say what to log and test; this says how, with LogTape.

For the API itself, read the sections you need of LogTape's own agent skill, which ships in the package (`node_modules/@logtape/logtape/skills/logtape/SKILL.md`; long, so find them by its headings, e.g. configuration, sinks, testing), or check its docs (e.g. through Context7), rather than working from memory: export names and options change between versions. Facts below were checked against LogTape 2.4; if neither source is available, say in your report which other exports you used unchecked.

## Setting it up

The application configures LogTape once, in one module of its own, which every other module imports its logger from. A library never calls `configure()`: it only calls `getLogger()` under its own name, and the application decides where its records go.

```ts
import { configure, getConsoleSink, getLogger, jsonLinesFormatter, reset, type Logger, type LogLevel } from '@logtape/logtape'
import { getPrettyFormatter } from '@logtape/pretty' // a separate package; core's `ansiColorFormatter` is the alternative

export const ROOT = 'my-service' // the app's own root category, not LogTape's root `[]`

let configured: Promise<void> | undefined

const configureOnce = async (level: LogLevel, development: boolean): Promise<void> => {
  await configure({
    sinks: {
      // Readable while developing, one JSON object per line for log collectors elsewhere
      console: getConsoleSink({ formatter: development ? getPrettyFormatter() : jsonLinesFormatter })
    },
    loggers: [
      { category: [ROOT], sinks: ['console'], lowestLevel: level },
      // LogTape's own diagnostics (a failing sink, a bad configuration)
      { category: ['logtape', 'meta'], sinks: ['console'], lowestLevel: 'warning' }
    ]
  })
}

// Safe to call more than once: `configure()` itself throws `ConfigError` ("Already configured") on a second call
export const configureLogging = async (level: LogLevel, development: boolean): Promise<void> => {
  await (configured ??= configureOnce(level, development))
}

export const getAppLogger = (area: string): Logger => getLogger([ROOT, area])

export const resetLogging = async (): Promise<void> => {
  configured = undefined
  await reset()
}
```

- **Configure once, and make a second call harmless.** `configure()` throws `ConfigError` if LogTape is already configured, unless it's passed `reset: true`. Hot reload, a second entry point or a framework calling the start-up hook again all call it twice, so keep the promise and return it. Read and validate settings before the guard: a rejected promise stays cached, which is acceptable only because a failed start-up stops the process. Where the toolchain duplicates or re-runs modules (e.g. a framework's server bundles), keep it on `globalThis` instead of in a module variable, as the framework's guidance says (`design.md`, "Module state and bundlers"; for Next.js, the `nextjs:nextjs-module-state` skill).
- **Give the app its own root category**, and hang each area off it (`[ROOT, 'invoices']`). Configuring LogTape's root `[]` instead sends every dependency that logs through LogTape to the app's sinks at the app's level; add a dependency's category as its own entry, with its own level, when its records are wanted.
- **Configure the meta logger** (`['logtape', 'meta']`, written as an array) with a sink at `warning`, so a failing sink or bad configuration is visible. Without an entry, its messages go through whatever covers its category, or a built-in fallback.
- **Read the level once, at start-up, and fail on a bad value.** `parseLogLevel` is case-insensitive and throws a `TypeError` on anything else; `isLogLevel` is a case-sensitive type guard. Neither accepts `warn` for `warning`: map it yourself if the environment variable should take it. Wrap the failure in the project's configuration error (or, if it has none, an `Error` subclass: `idioms.md` §8), so a typo stops the start rather than logging at a level nobody chose.
- **To send records to OpenTelemetry,** add `getOpenTelemetrySink({ loggerProvider })` from `@logtape/otel` (2.4 depends on older OpenTelemetry API packages of its own, but a provider from the 3.x SDK works with it, types included), giving it the SDK's `LoggerProvider` so records share its resource and exporters (`opentelemetry.md`). Pass a view with only its `getLogger` (`{ getLogger: provider.getLogger.bind(provider) }`), so the SDK alone owns the provider: given the provider itself, the sink shuts it down whenever LogTape is disposed or reset (`dispose()`, `reset()`, `configure({ reset: true })`), which stops log export for the rest of the process and makes the SDK's own shutdown warn that it was already shut down. An `Error` in a record's properties becomes the `exception.type`, `exception.message` and `exception.stacktrace` attributes (its `exceptionAttributes` option, `"semconv"` by default). If console output is also forwarded to telemetry, give the console sink the console from before forwarding (its `console` option), or each record is sent twice.
- **Flush before the process exits.** Call `await dispose()` on shutdown; a non-blocking or stream sink can otherwise lose what it has buffered. With telemetry, do it in the same handler as the SDK's shutdown, in this order: stop taking work (e.g. close the server), `await dispose()`, then `await sdk.shutdown()` (`opentelemetry.md`, "Starting it"), then exit. Two separate `SIGTERM` handlers race each other.
- **Request context** (`withContext({ requestId }, () => …)`) only works when `configure()` was given `contextLocalStorage: new AsyncLocalStorage()`.

Getting a logger at module level (`const logger = getAppLogger('invoices')`) is fine before `configure()` runs: the configuration is looked up when a record is logged. Until `configure()` runs, records go nowhere, so tests that don't care about logs need no set-up.

## Writing a log line

| The skill says | With LogTape |
|---|---|
| Values as properties, message constant | `logger.warn('Invoice {invoiceId} has no lines', { invoiceId })`. `{name}` is filled from the property of that name; never build the message with `${…}` or `+` |
| Pass the error object itself | `logger.error('Failed to load invoice {invoiceId}', { invoiceId, error })`, or the overload `logger.error('Failed to load invoice', error)`, which stores it as `error`. Don't add `{error}` to the message for the sake of the output: the JSON Lines formatter serialises an `Error` with its name, message, stack and cause, and the OpenTelemetry sink turns it into `exception.*` attributes |
| Levels | `trace`, `debug`, `info`, `warning`, `error`, `fatal`; `logger.warn()` is the same as `logger.warning()` |
| Summaries carry the detail | the lists as properties: `logger.info('Invalidated {count} tags', { count: tags.length, tags })` |
| Expensive diagnostics | pass a callback, which only runs when the level is enabled: `logger.debug('Response {body}', () => ({ body: summarise(response) }))`. An `async` callback makes the call return a promise: `await` it |
| No secrets | keep them out of properties; `@logtape/redaction` can redact by field name or pattern as a backstop, not a substitute |

## Testing

Assert a log line only where it's part of the contract (`writing-tests`). LogTape's configuration is global, so:

- **One shared helper** configures LogTape to capture records in memory, and every test that asserts logs uses it, rather than each test file writing its own sink. Once LogTape 2.5 is released (2.4 has only pre-releases of it), `@logtape/testing`'s `createLogRecorder()` returns a recorder whose `sink` goes in the configuration and whose `assertLogged()` checks a record; until then:

```ts
import { configure, type LogRecord } from '@logtape/logtape'
import { resetLogging, ROOT } from '../logging'

export const captureLogs = async (): Promise<LogRecord[]> => {
  const records: LogRecord[] = []

  await configure({
    reset: true,
    sinks: { capture: (record) => { records.push(record) } },
    loggers: [
      { category: [ROOT], sinks: ['capture'], lowestLevel: 'trace' },
      { category: ['logtape', 'meta'], sinks: [] }
    ]
  })

  return records
}

// After each test that captured logs
export const stopCapturingLogs = resetLogging
```

- **Reset after each test** with the app's own reset (which clears its once-guard as well as calling LogTape's `reset()`), so neither the capture nor the guard leaks into the next test. Don't run tests that capture logs concurrently with each other; if they must, LogTape's `withConfig()` (2.3 and later) scopes a configuration to one async context, given `contextLocalStorage` in the global one.
- **Assert what the contract fixes:** usually the level, the category and that the values are present, not the property names or the wording. `record.message` is an array of text and values in turn; join it (`record.message.map(String).join('')`) for the rendered text.

## Common mistakes

- **Calling `configure()` from a module that may load twice,** without a once-guard: the second call throws `ConfigError`.
- **Configuring LogTape's root category `[]`** for the app, which pulls in every dependency's LogTape records at the app's level.
- **No `dispose()` at shutdown,** losing buffered records.
- **`{error}` in the message** to get the stack into the output, which the formatters and the OpenTelemetry sink already do.
- **A capture sink written in each test file** instead of one shared helper, and a test that resets LogTape but not the app's own once-guard.

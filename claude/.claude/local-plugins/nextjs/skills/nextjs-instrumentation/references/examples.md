# Examples

Starting points for each module in the skill's layout, with LogTape and OpenTelemetry's Node SDK. Adapt them to the project's names, folders, logger and configuration helpers; they aren't meant to be copied whole. Paths (`./lib/…`) and variable names (`TELEMETRY_ENABLED`, `LOG_LEVEL`) are placeholders. Check every package against the installed version's types: `typescript-best-practices`' `references/opentelemetry.md` says which APIs are moving.

The logging modules aren't shown: `lib/logging/index.ts` exports `getAppLogger` (edge-safe), `lib/logging/log-level.ts` reads the level, and `lib/logging/configure-logging.ts` exports `configureLogging` (once, on `globalThis`, with an OpenTelemetry sink when given a logger provider) and `disposeLogging`. `typescript-best-practices`' `references/logtape.md` has them.

## `instrumentation.ts`

```ts
import type { Instrumentation } from 'next'
// Imported in the edge build too, so neither module may import anything Node-only: `reported-errors` imports nothing,
// and the logging module's Node-only parts (the OpenTelemetry sink) are in `configure-logging`, imported below
import { markErrorReported } from './lib/logging/reported-errors'
import { getAppLogger } from './lib/logging'

export async function register (): Promise<void> {
  // Must stay this literal condition, not an early return: Next drops the block from the edge build
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    const telemetry = process.env.TELEMETRY_ENABLED === 'true' ? (await import('./lib/telemetry')).startTelemetry() : undefined

    const { configureLogging, disposeLogging } = await import('./lib/logging/configure-logging')
    await configureLogging({ loggerProvider: telemetry?.loggerProvider })

    // One flush, run once, for the signal handler and the guards: the logger first, then the SDK
    const { flushOnce } = await import('./lib/flush')
    const flush = flushOnce([disposeLogging, ...(telemetry ? [telemetry.shutdown] : [])])

    // Next ignores anything `register` returns, so telemetry is flushed when the process is told to stop. Next
    // handles the signals itself unless NEXT_MANUAL_SIG_HANDLE is set (to any value): then the app flushes and exits,
    // and requests in progress are cut off. Otherwise this listener races Next's own exit and usually loses.
    if (process.env.NEXT_MANUAL_SIG_HANDLE) {
      // The codes Next 16's own handler exits with (128 plus the signal's number)
      const exitCodes = { SIGTERM: 143, SIGINT: 130 } as const
      for (const signal of ['SIGTERM', 'SIGINT'] as const) {
        process.once(signal, () => { void flush().finally(() => process.exit(exitCodes[signal])) })
      }
    } else {
      process.once('SIGTERM', () => { void flush() })
    }

    const { registerProcessGuards } = await import('./lib/process-guards')
    registerProcessGuards({ flush })
    getAppLogger('instrumentation').info('Process guards registered')

    // Fails fast: a missing variable stops the server starting rather than failing its first request
    const { readConfig } = await import('./lib/config')
    readConfig()
  }
}

// An edge route's error reaches the Node runtime from another realm, so it fails `instanceof Error`: keep its name,
// message and stack in an `Error` of this realm, which the exporter turns into `exception.*` attributes
const toError = (value: unknown): Error => {
  if (value instanceof Error) return value
  if (typeof value === 'object' && value !== null && 'message' in value) {
    const error = new Error(String(value.message))
    if ('name' in value && typeof value.name === 'string') error.name = value.name
    if ('stack' in value && typeof value.stack === 'string') error.stack = value.stack
    return error
  }
  return new Error(String(value))
}

export const onRequestError: Instrumentation.onRequestError = (error, request, context) => {
  // So the console bridge doesn't send it again when Next prints it
  markErrorReported(error)

  getAppLogger('request').error('Request failed', {
    error: toError(error),
    method: request.method,
    // Without the query string, which can carry a token
    path: request.path.split('?')[0],
    routerKind: context.routerKind,
    routePath: context.routePath,
    routeType: context.routeType,
    renderSource: context.renderSource,
    revalidateReason: context.revalidateReason
  })
}
```

## Flush

```ts
const MAX_FLUSH_MS = 5_000 // inside a typical stop grace period

// Runs the steps in order, once however many callers ask, and never takes longer than the limit
export const flushOnce = (steps: ReadonlyArray<() => Promise<void>>): () => Promise<void> => {
  let flushing: Promise<void> | undefined

  const run = async (): Promise<void> => {
    for (const step of steps) {
      try { await step() } catch (error) { console.error('Flush step failed', error) }
    }
  }

  return () => (flushing ??= Promise.race([run(), new Promise<void>((resolve) => { setTimeout(resolve, MAX_FLUSH_MS).unref() })]))
}
```

## Telemetry

The SDK's logger provider is `logs.getLoggerProvider()`: from `@opentelemetry/api` with the 3.x SDK (`sdk-node` 0.3xx), which no longer sets `@opentelemetry/api-logs`'s separate global, so nothing is exported through that one; from `@opentelemetry/api-logs` before the 3.x SDK. Check which the installed SDK registers.

```ts
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node'
import { logs, type LoggerProvider } from '@opentelemetry/api' // `@opentelemetry/api-logs` before the 3.x SDK (above)
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-proto'
import { NodeSDK } from '@opentelemetry/sdk-node'
import { getLogLevel } from './logging/log-level'
import { bridgeConsole } from './logging/console-bridge'
import { dropSpanTypes } from './span-filter'
import { installDiagLogger } from './diag-logger'

export interface Telemetry {
  // A view with only `getLogger`, so the logging library can't shut the SDK's provider down
  loggerProvider: Pick<LoggerProvider, 'getLogger'>
  shutdown: () => Promise<void>
}

export const startTelemetry = (): Telemetry => {
  // `NodeSDK`'s constructor installs its own diagnostic logger only when OTEL_LOG_LEVEL is set. Unset, install ours
  // first, so the constructor's own warnings (e.g. deprecated options) are seen; set, install ours after, to replace it
  const sdkInstallsDiagLogger = process.env.OTEL_LOG_LEVEL !== undefined
  if (!sdkInstallsDiagLogger) installDiagLogger()

  const sdk = new NodeSDK({
    serviceName: 'my-app',
    // No exporters: OTLP for all three signals, configured by the standard OTEL_* variables
    instrumentations: [
      getNodeAutoInstrumentations({
        '@opentelemetry/instrumentation-dns': { enabled: false },
        '@opentelemetry/instrumentation-net': { enabled: false },
        // Next makes the span for each incoming request; this keeps outgoing `http` calls. Not
        // `ignoreIncomingRequestHook`, which stops every span in the request
        '@opentelemetry/instrumentation-http': { disableIncomingRequestInstrumentation: true },
        // Pages Router: Next makes no `fetch` spans, so these are the only ones. With an App Router, keep it and set
        // NEXT_OTEL_FETCH_DISABLED=1 (exactly `1`), so each call isn't traced twice
        '@opentelemetry/instrumentation-undici': { enabled: true }
      })
    ],
    // `traceExporter` rather than `spanProcessors`, so the SDK still batches with the OTEL_BSP_* settings. With no `url`,
    // the exporter reads OTEL_EXPORTER_OTLP_ENDPOINT. Choosing an exporter fixes the traces' protocol (this one is
    // http/protobuf), so OTEL_EXPORTER_OTLP_PROTOCOL only applies to metrics and logs
    traceExporter: dropSpanTypes(new OTLPTraceExporter())
  })

  if (sdkInstallsDiagLogger) installDiagLogger()
  sdk.start()

  const provider = logs.getLoggerProvider()
  // Next's and libraries' console output, at or above the app's log level
  const unbridge = bridgeConsole({ level: getLogLevel(), logger: provider.getLogger('my-app/console') })

  return {
    loggerProvider: { getLogger: provider.getLogger.bind(provider) },
    shutdown: async () => {
      unbridge()
      await sdk.shutdown()
    }
  }
}
```

The SDK's options (`spanProcessors` versus `traceExporter`, sampling, the metric interval) are in `typescript-best-practices`' `references/opentelemetry.md`. Flush the logger before `sdk.shutdown()` (LogTape's `dispose()`; `references/logtape.md`).

## Span filter

```ts
import type { ExportResult } from '@opentelemetry/core'
import type { ReadableSpan, SpanExporter } from '@opentelemetry/sdk-trace' // `sdk-trace-base` before the 3.x SDK

// Next's span types that cost more than they tell, found by running the app against a local collector
export const DROPPED_SPAN_TYPES: readonly string[] = ['Instrumentation.loadModule', 'LoadComponents.loadRouteModule']

export const dropSpanTypes = (inner: SpanExporter, dropped: readonly string[] = DROPPED_SPAN_TYPES): SpanExporter => ({
  export: (spans: ReadableSpan[], done: (result: ExportResult) => void) => {
    inner.export(spans.filter((span) => !dropped.includes(String(span.attributes['next.span_type']))), done)
  },
  forceFlush: async () => { await inner.forceFlush?.() },
  shutdown: () => inner.shutdown()
})
```

## Diagnostic logger

```ts
import { diag, DiagConsoleLogger, DiagLogLevel, type DiagLogger } from '@opentelemetry/api'
import { diagLogLevelFromString } from '@opentelemetry/core'

// Warnings known to be noise. Next 15 times some spans with counters shared across requests, so under load the SDK
// sees an end before the start
const SUPPRESSED_WARNING_PREFIXES = ['Inconsistent start and end time, startTime > endTime.']

// At OTEL_LOG_LEVEL, or `warn` when it's unset, so a failing exporter is never silent
export const installDiagLogger = (): void => {
  const level = process.env.OTEL_LOG_LEVEL
  const logLevel = (level ? diagLogLevelFromString(level) : undefined) ?? DiagLogLevel.WARN
  const delegate: DiagLogger = new DiagConsoleLogger()

  diag.setLogger({
    ...delegate,
    warn: (message, ...args) => {
      if (!SUPPRESSED_WARNING_PREFIXES.some((prefix) => message.startsWith(prefix))) {
        delegate.warn(message, ...args)
      }
    }
  }, { logLevel, suppressOverrideMessage: true })
}
```

## Console bridge

Telemetry installs it before logging is configured; give LogTape's console sink `unbridgedConsole()` (its `console` option), or the app's own records are sent twice. The marker `onRequestError` calls is in a module of its own, `reported-errors.ts`, which imports nothing, as `instrumentation.ts` imports it in the edge build too.

`reported-errors.ts`:

```ts
declare global {
  // Errors `onRequestError` has logged; on `globalThis`, as it and the bridge run in different bundles
  var __reportedErrors: { objects: WeakSet<object>, stacks: Set<string> } | undefined
}

const MAX_REPORTED_STACKS = 100

const reportedErrors = () => (globalThis.__reportedErrors ??= { objects: new WeakSet(), stacks: new Set() })

export const markErrorReported = (error: unknown): void => {
  if (typeof error !== 'object' || error === null) return
  const { objects, stacks } = reportedErrors()
  objects.add(error)
  if (error instanceof Error && error.stack) {
    stacks.add(error.stack)
    // Next prints a page's error a second time from a copy, which only the stack matches
    if (stacks.size > MAX_REPORTED_STACKS) {
      const [oldest] = stacks
      if (oldest) stacks.delete(oldest)
    }
  }
}

export const isReported = (value: unknown): boolean => {
  if (typeof value !== 'object' || value === null) return false
  const { objects, stacks } = reportedErrors()
  return objects.has(value) || (value instanceof Error && !!value.stack && stacks.has(value.stack))
}
```

`console-bridge.ts`:

```ts
import { compareLogLevel, type LogLevel } from '@logtape/logtape'
import { context, SeverityNumber, type Logger as OtelLogger } from '@opentelemetry/api' // `@opentelemetry/api-logs` before the 3.x SDK, for all but `context`
import { isReported } from './reported-errors'

const METHODS = ['debug', 'log', 'info', 'warn', 'error'] as const
type Method = typeof METHODS[number]

const SEVERITY: Record<Method, { level: LogLevel, severityNumber: SeverityNumber, severityText: string }> = {
  debug: { level: 'debug', severityNumber: SeverityNumber.DEBUG, severityText: 'DEBUG' },
  log: { level: 'info', severityNumber: SeverityNumber.INFO, severityText: 'INFO' },
  info: { level: 'info', severityNumber: SeverityNumber.INFO, severityText: 'INFO' },
  warn: { level: 'warning', severityNumber: SeverityNumber.WARN, severityText: 'WARN' },
  error: { level: 'error', severityNumber: SeverityNumber.ERROR, severityText: 'ERROR' }
}

// Next prints a page's error before calling `onRequestError`, so output carrying an error waits this long
const REPORT_WAIT_MS = 1000

const render = (value: unknown): string => {
  if (typeof value === 'string') return value
  if (value instanceof Error) return value.stack ?? `${value.name}: ${value.message}`
  try { return JSON.stringify(value) } catch { return String(value) }
}

let original: Console | undefined
export const unbridgedConsole = (): Console => original ?? console

export interface ConsoleBridgeOptions {
  level: LogLevel // the app's own, so the bridge sends what the app's logging would
  logger: Pick<OtelLogger, 'emit'>
  ignore?: readonly RegExp[] // known noise, e.g. a library's harmless warning
}

// Returns a function that restores the console
export const bridgeConsole = ({ level, logger, ignore = [] }: ConsoleBridgeOptions): () => void => {
  const originals = { ...console }
  original = originals

  for (const method of METHODS) {
    const { level: methodLevel, severityNumber, severityText } = SEVERITY[method]

    console[method] = (...args: unknown[]): void => {
      originals[method].apply(console, args)
      if (compareLogLevel(methodLevel, level) < 0) return

      const body = args.map(render).join(' ')
      if (ignore.some((pattern) => pattern.test(body))) return

      // Taken now, so a record sent later keeps its time and its request's trace
      const record = { severityNumber, severityText, body, timestamp: new Date(), context: context.active() }
      const send = (): void => { if (!args.some(isReported)) logger.emit(record) }

      if (args.some((arg) => arg instanceof Error)) {
        // Unreferenced, so a waiting record never keeps the process alive
        setTimeout(send, REPORT_WAIT_MS).unref()
      } else {
        send()
      }
    }
  }

  return () => { Object.assign(console, originals); original = undefined }
}
```

## Process guards

```ts
const WINDOW_MS = 60_000 // the sliding window rejections are counted over
const MAX_REJECTIONS = 25 // tolerated within it before the process exits
const MAX_FLUSH_WAIT_MS = 2_000 // in case stdout or stderr never drains

// `process.exit` drops pending writes, which would lose the line explaining the exit
const exitAfterFlush = (code: number): void => {
  let exited = false
  const exitOnce = (): void => { if (!exited) { exited = true; process.exit(code) } }
  setTimeout(exitOnce, MAX_FLUSH_WAIT_MS).unref()
  let pending = 2
  const drained = (): void => { if (--pending === 0) exitOnce() }
  process.stdout.write('', drained)
  process.stderr.write('', drained)
}

// Logging must never be what stops the exit (e.g. `console.error` on a closed stdout)
const safeLog = (...args: unknown[]): void => { try { console.error(...args) } catch { /* nothing more to do */ } }

declare global {
  var __processGuardsRegistered: boolean | undefined
}

// Next already logs every unhandled rejection and uncaught exception and keeps running; these decide when to stop.
// Exiting relies on something restarting the process (the container platform, or a supervisor on a VM).
export const registerProcessGuards = ({ flush }: { flush: () => Promise<void> }): void => {
  // Telemetry first, so the exit's own records are sent, then the console
  const exit = (): void => { void flush().finally(() => { exitAfterFlush(1) }) }

  if (globalThis.__processGuardsRegistered) return
  globalThis.__processGuardsRegistered = true

  let rejections: number[] = []

  process.on('unhandledRejection', () => {
    const now = Date.now()
    rejections = [...rejections.filter((at) => at > now - WINDOW_MS), now]
    if (rejections.length >= MAX_REJECTIONS) {
      safeLog(`[process-guards] ${rejections.length} unhandled rejections within ${WINDOW_MS} ms; exiting`)
      exit()
    }
  })

  // The process's state may be corrupt: exit, and let the platform start a clean one
  process.on('uncaughtException', () => {
    safeLog('[process-guards] uncaught exception; exiting')
    exit()
  })
}
```

## Health route

Pages Router, `pages/api/health.ts`:

```ts
import type { NextApiRequest, NextApiResponse } from 'next'

// Says the server is up and answering. It checks nothing else, so an outage elsewhere doesn't get it restarted
export default function handler (_: NextApiRequest, res: NextApiResponse): void {
  res.setHeader('Cache-Control', 'no-store')
  res.status(200).send('ok')
}
```

App Router, `app/api/health/route.ts`:

```ts
import { connection } from 'next/server'

// Says the server is up and answering. It checks nothing else, so an outage elsewhere doesn't get it restarted
export async function GET (): Promise<Response> {
  // Answered per request: with `cacheComponents`, a constant response would be prerendered at build time
  await connection()
  return new Response('ok', { headers: { 'Cache-Control': 'no-store' } })
}
```

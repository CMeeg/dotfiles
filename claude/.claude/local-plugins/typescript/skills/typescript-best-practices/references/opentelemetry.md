# OpenTelemetry in Node.js

How to apply the `instrumentation-and-logging` and `writing-tests` skills with OpenTelemetry's Node SDK (`@opentelemetry/sdk-node`). Those skills say what to collect and test; this says how, with the SDK. A framework that starts telemetry through a hook of its own (e.g. an `instrumentation` file) has its own reference, which adds to this one.

Each package named here is a dependency to agree before adding, if the project doesn't have it. Check the installed versions' types before relying on an option or constructor: the JavaScript SDK's packages change shape between major versions (the `0.x` packages are still experimental), and docs from the main branch (e.g. through Context7) can show names the installed version doesn't have. Facts below were checked against `@opentelemetry/sdk-node` 0.301, the 3.1 SDK packages and `@opentelemetry/api` 1.10. The 3.x SDK differs from the 2.x SDK (`sdk-node` 0.2xx) in three places:

- **Traces:** `@opentelemetry/sdk-trace` replaces `@opentelemetry/sdk-trace-base` and `@opentelemetry/sdk-trace-node`, which are deprecated. Its provider is `TracerProvider`, which has no `register()`, and its span processors take `{ exporter }` rather than the exporter itself.
- **Logs API:** it's in `@opentelemetry/api` (`logs`, `SeverityNumber`). `@opentelemetry/api-logs` keeps a global of its own, which the 3.x SDK doesn't set, so a logger provider read from it exports nothing.
- **Start-up:** `sdk-node` also exports an experimental `startNodeSdk`; `new NodeSDK(…)` and `sdk.start()` are still the documented form.

## Starting it

The SDK has to start before the application's modules load, or the libraries it instruments are already loaded unpatched. Put the set-up in a file of its own and load it with Node's `--import` (ES modules) or `--require` (CommonJS), rather than importing it from the entry point:

```json
"start": "node --experimental-loader=@opentelemetry/instrumentation/hook.mjs --import ./dist/telemetry.js dist/main.js"
```

- **An ES-module app needs the loader hook as well** (`--experimental-loader=@opentelemetry/instrumentation/hook.mjs`, on the command line or in `NODE_OPTIONS`). Without it, instrumentations that patch modules (`http`, web frameworks, database clients) silently do nothing; only those that listen on Node's diagnostics channels (e.g. `undici`, which covers `fetch`) work. The hook is part of the documented set-up, not an optional extra: the command names `@opentelemetry/instrumentation`, so it should be a direct dependency (on the same `0.x` line as `@opentelemetry/sdk-node`) rather than arriving through another package; ask before adding it, as for any dependency. Node prints an `ExperimentalWarning` for the flag, which is expected: the SDK's docs plan to move to `module.register()`, which isn't the documented form yet.
- **Let the environment configure the exporters.** With no exporters passed, `NodeSDK` exports traces, metrics and logs over OTLP, configured by the standard variables (`OTEL_EXPORTER_OTLP_ENDPOINT`, `_PROTOCOL`, `_HEADERS`, `OTEL_METRIC_EXPORT_INTERVAL`, `OTEL_SDK_DISABLED`, and `OTEL_TRACES_EXPORTER`, `OTEL_METRICS_EXPORTER` and `OTEL_LOGS_EXPORTER`, which take `none`). Pass exporters only for a backend that isn't OTLP, and then you take over what the environment did: an explicitly created `PeriodicExportingMetricReader` doesn't read `OTEL_METRIC_EXPORT_INTERVAL` (read it yourself), and an exporter's `url` option is used as given, whereas `OTEL_EXPORTER_OTLP_ENDPOINT` has `/v1/traces` (or `/v1/metrics`, `/v1/logs`) appended.
- **Options are plural, and processors take an options object.** `metricReaders` and `logRecordProcessors` (the singular `metricReader` is deprecated). Span and log record processors take `{ exporter }`.
- **To change only the trace exporter** (e.g. to wrap it in a filter), pass it as `traceExporter`: the SDK batches it with the `OTEL_BSP_*` settings. Passing `spanProcessors` instead takes batching over, and those variables no longer apply. Choosing an exporter also fixes the traces' protocol (e.g. `exporter-trace-otlp-proto` is http/protobuf), so `OTEL_EXPORTER_OTLP_PROTOCOL` then applies only to metrics and logs.

```ts
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node'
import { NodeSDK } from '@opentelemetry/sdk-node'

const sdk = new NodeSDK({
  serviceName: 'my-service',
  // No exporters or sampler: OTLP for all three signals, and sampling from OTEL_TRACES_SAMPLER and OTEL_TRACES_SAMPLER_ARG
  instrumentations: [getNodeAutoInstrumentations()]
})

sdk.start()

// Flushes what's buffered, then lets the signal end the process as it would have without this listener
process.once('SIGTERM', () => {
  sdk.shutdown().catch((error: unknown) => { console.error('Telemetry did not flush', error) }).finally(() => { process.kill(process.pid, 'SIGTERM') })
})
```

## Applying the skill's set-up rules

| The skill says | With the Node SDK |
|---|---|
| Honour the standard variables | prefer the environment to code, as above. A value passed in code wins over its variable: a `sampler` over `OTEL_TRACES_SAMPLER`, and `serviceName` over `OTEL_SERVICE_NAME` |
| One resource for traces, metrics and logs | let `NodeSDK` create all three providers, rather than building a `LoggerProvider` of your own beside it. Its resource is the `resource` option, overridden by detected attributes (`OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`, host, process), overridden by `serviceName`: choose `resource` or `serviceName` by whether the environment may rename the service. A logging library's bridge gets the SDK's provider (`logs.getLoggerProvider()` from `@opentelemetry/api`, after `sdk.start()`), as a view with only `getLogger` if the bridge would otherwise shut it down (LogTape's does: `logtape.md`); left to itself, a bridge may build its own provider with a different resource |
| The same sampler everywhere, only the ratio differing | pass `new ParentBasedSampler({ root: new TraceIdRatioBasedSampler(ratio) })` (both from `@opentelemetry/sdk-trace`) with the ratio for the environment, but only when `OTEL_TRACES_SAMPLER` isn't set, so a deployment that forgets to configure sampling gets the safe ratio and one that sets the standard variables still can. Parent-based, so a trace is kept or dropped whole. Worth a small function of its own, tested without the SDK |
| Make export failures visible | `NodeSDK` installs a diagnostic logger only when `OTEL_LOG_LEVEL` is set. When it isn't, install one at `warn` yourself, before `new NodeSDK(…)`, as its constructor warns about deprecated options and unsupported exporter values: `diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.WARN)`. When it is set, leave it to the SDK. Keep it apart from the app's own log level |
| Create meters and counters lazily | the API has proxies for tracers and loggers but not meters: a meter or counter taken before `sdk.start()` stays a no-op for the life of the process. See "Custom metrics" |
| Flush on shutdown | `sdk.shutdown()` flushes all three signals. Call it from your own `SIGTERM` listener (above); if the app handles `SIGTERM` itself (e.g. to close its server), call it from there after the server closes and drop the listener, as both would run. Flush a logging library first (LogTape's `dispose()`: `logtape.md`), so its last records reach the provider before it shuts down. A framework may ignore a shutdown function returned to it, and one that handles `SIGTERM` itself may exit before your listener's flush finishes: check, and if it can, take the signal over (e.g. Next.js's `NEXT_MANUAL_SIG_HANDLE`, in the `nextjs:nextjs-instrumentation` skill) |
| Filter noise at the source | `getNodeAutoInstrumentations({ '@opentelemetry/instrumentation-dns': { enabled: false } })`, or `OTEL_NODE_DISABLED_INSTRUMENTATIONS=dns,net` (short names; `fs` and `host-metrics` are off by default); health checks through `@opentelemetry/instrumentation-http`'s `ignoreIncomingRequestHook` (which stops every span in the request, as wanted for a health check), or in the sampler where a framework makes the request's span; a framework's internal spans by wrapping the span exporter in one that drops them by attribute. If the framework already makes a span per incoming request, stop the `http` instrumentation making a second one with `disableIncomingRequestInstrumentation: true`, which keeps its spans for outgoing calls; disable it only if the app makes none. Not `ignoreIncomingRequestHook: () => true`, which runs the request inside `suppressTracing`, so nothing in it is traced |

## Custom spans and metrics

- **Spans:** a tracer taken before the SDK starts works once it starts (the API hands out a proxy), but it then stays bound to the first provider it reached, so where tests install a provider per test, take the tracer when it's used rather than once at module level. Use `tracer.startActiveSpan(name, { attributes }, async (span) => …)`, and on failure `span.recordException(error)` and `span.setStatus({ code: SpanStatusCode.ERROR })`, ending the span in `finally`.
- **Metrics:** look instruments up for the meter provider in place when they're used, not once when the module loads or first uses them, so they count once the SDK starts and a test's provider is the one used. Either take a `Meter` as a parameter (`design.md`, "Dependencies are parameters"), or key them by provider:

```ts
import { metrics, type Counter, type MeterProvider } from '@opentelemetry/api'

const countersByProvider = new WeakMap<MeterProvider, Counter>()

const ordersPlaced = (): Counter => {
  const provider = metrics.getMeterProvider()
  let counter = countersByProvider.get(provider)

  if (!counter) {
    counter = provider.getMeter('my-service/orders').createCounter('orders.placed', { unit: '{order}', description: 'Orders paid for and placed' })
    countersByProvider.set(provider, counter)
  }

  return counter
}
```

- **No unbounded attributes on metrics:** an ID per data point makes a time series per ID. Put IDs on spans, and keep metric attributes to a small fixed set (an outcome, a route template).

## Testing

Unit tests don't start the SDK: they install providers that record in memory, through the API's globals, and remove them afterwards. The helper needs `@opentelemetry/context-async-hooks` (for the context manager) and `@opentelemetry/sdk-metrics` and `@opentelemetry/sdk-trace` as development dependencies, if the project doesn't have them. Check the SDK's wiring (exporters, resource, sampling) by running the app against a local collector or dashboard instead.

```ts
import { context, metrics, propagation, trace } from '@opentelemetry/api'
import { AsyncLocalStorageContextManager } from '@opentelemetry/context-async-hooks'
import { MeterProvider, MetricReader } from '@opentelemetry/sdk-metrics'
import { InMemorySpanExporter, SimpleSpanProcessor, TracerProvider } from '@opentelemetry/sdk-trace'

// Collects when the test asks, rather than exporting on a timer
class TestMetricReader extends MetricReader {
  protected async onShutdown (): Promise<void> {}
  protected async onForceFlush (): Promise<void> {}
}

export const recordTelemetry = () => {
  const reader = new TestMetricReader()
  const spans = new InMemorySpanExporter()
  metrics.setGlobalMeterProvider(new MeterProvider({ readers: [reader] }))
  // A context manager as well as the provider: without one, `startActiveSpan` makes no span active inside its callback
  context.setGlobalContextManager(new AsyncLocalStorageContextManager().enable())
  trace.setGlobalTracerProvider(new TracerProvider({ spanProcessors: [new SimpleSpanProcessor({ exporter: spans })] }))

  return {
    spans: () => spans.getFinishedSpans(),
    // A counter's total across its data points (sums only: a histogram's points aren't numbers)
    total: async (name: string): Promise<number> => {
      const { resourceMetrics } = await reader.collect()
      return resourceMetrics.scopeMetrics.flatMap((scope) => scope.metrics).filter((metric) => metric.descriptor.name === name)
        .reduce((sum, metric) => sum + metric.dataPoints.reduce((points: number, point) => points + Number(point.value), 0), 0)
    }
  }
}

// After each test
export const stopRecordingTelemetry = (): void => {
  metrics.disable()
  trace.disable()
  context.disable()
  propagation.disable()
}
```

- **A fresh provider per test** (`beforeEach`), with instruments and tracers looked up when used, as above, so each test starts from zero rather than comparing totals before and after.
- **Assert what the contract fixes:** a counter's total, a span's status or the attributes callers rely on, not span names or the order spans end in, unless something depends on them.
- **Logic in the set-up** (e.g. parsing a variable into an interval) is worth a test of its own; the SDK's behaviour isn't.

## Common mistakes

- **Importing the set-up from the entry point** instead of `--import`, so modules load before the SDK patches them.
- **No loader hook in an ES-module app,** so only `fetch` is traced and incoming requests aren't.
- **Exporters passed in code with nothing to say,** losing what the standard variables configure (the metric interval, the endpoint's signal path).
- **A second `LoggerProvider`** with a resource of its own, so logs and traces show as different services.
- **A counter created once at module level,** a no-op if the module loaded before the SDK started, and bound to the first test's provider in tests; a tracer taken once is bound the same way in tests.
- **A tracer provider without a context manager in a test,** so no span is active inside `startActiveSpan`.
- **A logger provider read from `@opentelemetry/api-logs` with the 3.x SDK,** which registers its provider on `@opentelemetry/api`, so nothing is exported.

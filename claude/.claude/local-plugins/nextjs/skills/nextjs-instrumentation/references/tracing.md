# Tracing

Part of the `nextjs-instrumentation` skill: the spans Next makes itself, and how the Node SDK's instrumentations fit around them. Starting the SDK, sampling and custom spans are in `typescript-best-practices`' `references/opentelemetry.md`.

## Next's own spans

- **A root span per request** (`next.span_type` `BaseServer.handleRequest`), carrying `http.method` and `http.target` (the path with its query) when it starts. With `proxy` (or middleware) there are two per request: the proxy's pass and the render's.
- **Render and route spans:** e.g. `Render.getServerSideProps`, `Render.getStaticProps`, `Render.renderDocument` and `Node.runHandler` (an API route) in the Pages Router; `AppRender.getBodyResult`, `AppRouteRouteHandlers.runHandler` and `NextNodeServer.createComponentTree` in the App Router; `NextNodeServer.findPageComponents`, `RouteModule.prepare` and `Middleware.execute` in both.
- **At start-up (16):** `Instrumentation.loadModule`, `Instrumentation.register`, and a root `LoadComponents.loadRouteModule` span for each route.
- **A span per `fetch`** (`AppRender.fetch`) wherever Next has patched the global `fetch`: see below.
- `NEXT_OTEL_VERBOSE=1` adds more.

## Incoming requests: the `http` instrumentation

Next makes the span for each incoming request, so stop the `http` instrumentation making a second one, while keeping its spans for outgoing `http` calls (clients that don't use `fetch`):

```ts
'@opentelemetry/instrumentation-http': { disableIncomingRequestInstrumentation: true }
```

**Not `ignoreIncomingRequestHook: () => true`:** an ignored request runs entirely inside `suppressTracing`, so nothing in it is traced, Next's own spans and outgoing calls included (`@opentelemetry/instrumentation-http` 0.301, observed under Next 16.4). Disable the instrumentation altogether only if the app makes no outgoing `http` calls.

## `fetch`: by router

`undici`'s instrumentation (on by default in `getNodeAutoInstrumentations`) traces every `fetch`. Next adds its own `AppRender.fetch` span wherever it has patched the global `fetch`, which is whenever the app has an App Router: in production it preloads every App Router entry at start and patches `fetch` then, so Pages Router calls get Next's spans too, from the first request.

| App | Next's own `fetch` spans | What to do |
|---|---|---|
| Pages Router only | none | keep `undici` on, or calls from `getStaticProps`, `getServerSideProps` and API routes don't appear |
| App Router, or both | every call | each call is traced twice: set `NEXT_OTEL_FETCH_DISABLED=1` (exactly `1`; `true` does nothing) and keep `undici`, so every call is traced once, the same way |

## Bundled packages

An instrumentation that patches a package as it loads (a database client, a logger) only sees a package Node loads from `node_modules`, not one bundled into the server's code.

- **The App Router bundles server dependencies,** unless the package is in `serverExternalPackages` or Next's default list of external packages (`node_modules/next/dist/lib/server-external-packages.json`, `.jsonc` in 16; it includes pino, but no OpenTelemetry or LogTape package). **The Pages Router** loads dependencies from `node_modules` unless `bundlePagesRouterDependencies` is on or the package is in `transpilePackages`.
- **The SDK itself:** under Turbopack (Next 16's default) it bundles into the instrumentation chunk and works without `serverExternalPackages`. Under webpack (Next 15, or 16 with `--webpack`), `@opentelemetry/auto-instrumentations-node` has needed to be in `serverExternalPackages`, as it loads instrumentations dynamically. If the build or the traces misbehave, try listing it.

## Noise

- **Drop span types that cost more than they tell** by wrapping the trace exporter in one that filters on `next.span_type`. Find them by running the app against a local collector or dashboard, not from a list: they differ by router and version (the start-up spans above are a likely first candidate).
- **Under load the SDK may drop spans:** "Dropped N spans because maxQueueSize reached". Raise `OTEL_BSP_MAX_QUEUE_SIZE` (which applies when the exporter is passed as `traceExporter`), or sample.
- **Next's span timing has tripped an SDK warning under load** in Next 15 (`Inconsistent start and end time, startTime > endTime.`); it didn't reproduce in 16.4. To drop a warning known to be noise, install a diagnostic logger of your own that filters it: after constructing `NodeSDK` when `OTEL_LOG_LEVEL` is set (the constructor installs one, which yours replaces), and before it at `warn` when it isn't (`typescript-best-practices`' `references/opentelemetry.md`). `examples.md` has one.

## `@vercel/otel`

It's what Next's docs suggest first: it runs on the edge too, but instruments only `fetch` (and `http` in Node). Self-hosted, with database or other clients to trace, use `NodeSDK`.

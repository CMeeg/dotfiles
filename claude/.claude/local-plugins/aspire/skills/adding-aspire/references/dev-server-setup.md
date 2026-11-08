# Set-up details for the dev server's resource

The details behind `SKILL.md`, step 4, for a dev server run by a TypeScript AppHost. Checked with Aspire 13.6; recheck any marked *observed* against the current version.

This example runs the project's own `dev` script unchanged with `addJavaScriptApp`, which adds no endpoint of its own. A framework-specific resource such as `addNextJsApp` adds its own endpoint on an Aspire-assigned port and passes the port as an argument: prefer it only when that suits the project.

The example passes options objects, as the generated SDK takes them in 13.6, while `aspire docs api get` prints signatures with positional parameters. Check each call against the generated types in the AppHost's `.aspire/` folder.

```ts
// The dev server sets its own NODE_EXTRA_CA_CERTS, so the exporters get Aspire's certificate explicitly.
const aspireCertificate = process.env.NODE_EXTRA_CA_CERTS;
if (!aspireCertificate) throw new Error('Run the AppHost with the Aspire CLI, which passes NODE_EXTRA_CA_CERTS.');

await builder
  .addJavaScriptApp('web', '..', { runScriptName: 'dev' })
  .withNpm({ install: false })                    // the app's packages are installed as usual
  .withHttpsEndpoint({ port: 3000, targetPort: 3000, isProxied: false, env: 'PORT' })
  .withHttpHealthCheck({ path: '/api/health', endpointName: 'https' })
  .withEnvironment('OTEL_LOG_LEVEL', 'warn')
  .withEnvironment('OTEL_EXPORTER_OTLP_CERTIFICATE', aspireCertificate);
```

- **A health route that checks no dependency.** Add a route that returns 200 as soon as the server answers (no database, CMS or API calls), and point `withHttpHealthCheck` at it. Then `aspire wait` means "answering requests" rather than "process started". A route that checks dependencies would show the server unhealthy whenever one is down, or call them on every poll. If the app already has a status route that checks its dependencies, add a separate one rather than reusing it. A probe over HTTPS has to trust the dev server's certificate. It did with `next dev --experimental-https`, whose CA is in the OS trust store (*observed*). If the resource never turns healthy while the page loads, check that first.
- **`OTEL_LOG_LEVEL=warn`.** The OpenTelemetry Node SDK (`NodeSDK`) installs its diagnostics logger only when this is set. Without it, a failed export (e.g. `self-signed certificate`) is silent and telemetry just stops. With it, the warning appears in `aspire logs <resource>`.
- **A dev server that sets its own `NODE_EXTRA_CA_CERTS`.** Aspire makes Node resources trust its dev certificate through `NODE_EXTRA_CA_CERTS`. A dev server that serves HTTPS with its own certificate authority can replace that for its server process (`next dev --experimental-https` does, *observed*), and the exporters then fail to reach the dashboard. The Aspire CLI also gives the AppHost process `NODE_EXTRA_CA_CERTS`, so pass that path to the resource as `OTEL_EXPORTER_OTLP_CERTIFICATE`. The Node OTLP exporters read it, both gRPC and HTTP. Fail loudly if it's missing (the AppHost was started without the CLI).
- **A fixed port, so a taken port fails rather than moves.** When the URL must stay the same (bookmarks, OAuth or webhook callbacks, a CMS preview), use `isProxied: false` with the same `port` and `targetPort`. Also pass the port to the server (`env: 'PORT'`): a dev server that picks another port when its own is taken leaves the dashboard showing the resource healthy while something else answers there. Given a port, it fails with `EADDRINUSE` instead: the resource shows as finished and `aspire logs` has the error. After `aspire stop`, the port stays taken for a few seconds while the server shuts down (about 8 in WSL, *observed*). Document both in the project skill's troubleshooting table.
- **`withNpm({ install: false })`** when installing needs credentials (a private feed token) or shouldn't run on every start.
- **Telemetry names.** If the app sets `service.name` itself, name the resource to match, or have the app prefer `OTEL_SERVICE_NAME`, which Aspire sets to the resource's name. `NodeSDK` reads the environment's attributes by default (its resource detectors include `envDetector`) and gives that resource to the providers it builds, so with it only the name has to match. A provider built outside it (e.g. a `LoggerProvider` constructed by hand) needs its resource built from the environment too, e.g. `detectResources({ detectors: [envDetector] })` merged with the app's own attributes. Otherwise logs miss Aspire's `service.instance.id` and appear under a separate resource from the traces.
- **Structured logs.** The dashboard's structured logs (and `aspire otel logs`) need the app to export logs through OpenTelemetry: a log exporter registered on the same SDK, so logs share the traces' resource, and a logger that writes through it. Without one, the app's logs are only console output, read with `aspire logs <resource>`. Raise adding one with the user, as it's a new dependency.
- **The development certificate.** The user, not the agent, runs the first `aspire run` interactively. In a non-interactive session on Windows or macOS, the CLI creates the certificate without trusting it. In WSL, the first run asked Windows to trust it (*observed*), so a Windows browser trusts the dashboard. A `PartiallyFailedToTrustTheCertificate` warning can be ignored if the dashboard loads.

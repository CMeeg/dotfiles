# Shutdown: flushing telemetry

Part of the `nextjs-instrumentation` skill. The SDK's own shutdown and the logger-then-SDK order are in `typescript-best-practices`' `references/opentelemetry.md` and `references/logtape.md`; this is what Next does around them.

- **Next ignores what `register()` returns,** so a shutdown function returned from it never runs (15.5 and 16.4).
- **Next's own handler:** under `next start` and the standalone `server.js`, Next handles `SIGTERM` and `SIGINT` itself: it closes the server, waits for the requests in progress, then exits (with 0 in 15.5; with 143 for `SIGTERM` and 130 for `SIGINT` in 16).
- **A `process.once('SIGTERM', …)` listener of your own loses that race.** It runs beside Next's handler, not before it. With no request in progress Next exits within about 100 ms, before anything is exported: with the SDK's default schedules that's up to the last 5 seconds of traces, 1 second of logs and 60 seconds of metrics. With a request in progress the flush may finish, but it shuts the SDK down before that request ends, so the request's own spans are lost.
- **For a flush that completes,** set `NEXT_MANUAL_SIG_HANDLE` in the process's environment (the start command or the container's `ENV`, not a `.env` file) and handle `SIGTERM` and `SIGINT` yourself: flush, then exit. Next only checks the variable is set, so any value turns its handler off, `false` and `0` included. The cost is that Next no longer waits for the requests in progress: they're cut off.
- **This is the user's choice:** losing the tail of the telemetry, or cutting off requests in progress. Say which you've assumed.
- **Exit as Next 16 does:** 128 plus the signal's number (143 for `SIGTERM`, 130 for `SIGINT`), so the platform sees the same codes either way.
- **`next dev` is different:** its parent process handles the signals whatever `NEXT_MANUAL_SIG_HANDLE` says, so don't rely on a flush there.
- **One flush, run once,** shared by the signal handler and the process guards, so an exit the guards decide on sends its telemetry too.
- **Give the platform's stop grace period room** for the drain and the flush.

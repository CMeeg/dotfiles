---
name: nextjs-module-state
description: Use when Next.js server code keeps an instance that must be shared (a cache, a client, a registry, a once-guard), when a module-level singleton turns out to have more than one copy, data cached by one route is missing in another, a client or connection pool is recreated on every save in development, or `instanceof` fails for an object or error made elsewhere in the app.
---

# Module state in Next.js

## Overview

A module is normally evaluated once, so a module-level instance (`export const cache = createCache()`) is shared by everything that imports it. In a Next.js server that doesn't hold: Next bundles server code into several bundles, so a module imported from more than one may be evaluated once in each, and the development server re-runs a module each time it's recompiled. Each copy creates its own instance, and its own classes.

Which routes share a copy depends on the router, the bundler and whether it's a production build, so don't rely on any pattern. In running apps on Next 15.5 and 16.4:

- **Always separate:** `instrumentation.ts`, each Pages Router page and API route, and the App Router from the Pages Router.
- **App Router routes vary:** under Turbopack (16's default) a page had its own copy while route handlers shared one, in production and development; under webpack (15, or 16 with `--webpack`) a production build shared one copy across pages and route handlers, while `next dev` gave each its own. So something that works in production can fail in development, and the other way round.
- **Development:** an edit made a new copy, while state on `globalThis` survived.

The general rule, a module-level instance by default, is in `typescript:typescript-best-practices`' `references/design.md`, "Module state and bundlers". This skill is the Next.js exception to it.

## Sharing an instance

Only for an instance that must be shared (a cache, a client, a registry, a once-guard), keep it on `globalThis` under a distinctive name, created on first use by a getter, so importing the module doesn't build it:

```ts
import { createCache, type Cache } from './create-cache'

declare global {
  // On `globalThis`, so every bundle (and each development recompile) shares one
  var __appCache: Cache | undefined
}

export const getAppCache = (): Cache => (globalThis.__appCache ??= createCache())
```

- **Declare its type with `declare global { var … }` in the module that owns it,** not in a central declarations file, so the name and its owner stay together.
- **One prefix for the names** (e.g. `__`), so they're recognisable and don't clash with a library's.
- **Everything else stays module-level:** a pure helper or a constant gains nothing from `globalThis`, which would only be a global under another name.

## Recognising objects across copies

Each bundle has its own copy of a class too, so `instanceof` misses an object another copy made: a value one route cached and another reads, or an error thrown by a shared client.

- **An error:** check its `name` (set in the subclass) rather than `instanceof`, with a type guard: `isUpstreamError = (error: unknown): error is UpstreamError => error instanceof Error && error.name === 'UpstreamError'`.
- **Another object:** mark it with a registered symbol (`Symbol.for('my-app.tagged-entry')`, the same in every copy) and check for that. In the runs above, the marker was recognised in every case where `instanceof` failed.
- **A package's classes are copied too** when Next bundles the package, under Turbopack and webpack alike: in the App Router by default, and in the Pages Router when it's in `transpilePackages` or `bundlePagesRouterDependencies` is on. A shared client from such a package throws errors that fail `instanceof` against the package's own classes imported elsewhere, including from the other router, which loads its own copy.
- **A package Node loads from `node_modules` has one copy for the whole process:** one in `serverExternalPackages`, or any package the Pages Router doesn't bundle (its default). Then `instanceof` against its own classes works across routes and both routers. A local package linked as a directory (`file:../pkg`, a workspace) resolves outside `node_modules` and may be bundled anyway; check.

## Testing

A test run evaluates a module once per test file, never once per route, so tests don't show any of this: a test passes with a module-level instance or an `instanceof` check that fails in the running app. Check sharing by running the app and using the instance from two kinds of route (e.g. a page and an API route), in development and in a production build, as they can differ.

## Common mistakes

- **A module-level singleton** for a cache or client, so each route has its own and development recreates it on every save.
- **Building the instance when the module loads** (`globalThis.__x = create()` at top level), rather than on first use.
- **`instanceof`** for errors or objects that may come from another bundle.
- **Concluding from a passing test** that an instance is shared.

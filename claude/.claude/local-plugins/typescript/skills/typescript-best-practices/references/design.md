# Design in TypeScript

How design principles (single responsibility, dependency inversion, open for extension, small interfaces, composition) usually look in TypeScript. The principles themselves, and when applying them is over-engineering, are in the `design-principles` skill. TypeScript's idiom is functions, closures and structural types; classes are the exception (an `Error` subclass, an interface a library makes you implement, or a project that already uses them). Match the project's existing shape first: these are the defaults when it has none.

## Dependencies are parameters

Pass collaborators in rather than importing or constructing them inside the logic. A factory takes them as one options object and returns the functions that use them; a single composition root (the module that builds the app's instances) wires the real ones; a test passes fakes.

```ts
type DirectoryDeps = {
  query: (sql: string, params: unknown[]) => Promise<unknown[]>;
  logger: Pick<Logger, "warn" | "error">;   // only what's used
  now?: () => Date;                          // optional, with a default
};

export const createUserDirectory = ({ query, logger, now = () => new Date() }: DirectoryDeps) => {
  const findActive = async (signal?: AbortSignal): Promise<User[]> => { /* uses query, logger, now */ };
  return { findActive };
};

// composition root
export const userDirectory = createUserDirectory({ query: db.query, logger: appLogger });

// test
const directory = createUserDirectory({ query: async () => [], logger: { warn: vi.fn(), error: vi.fn() } });
```

- **Depend on the narrowest type that works:** a function type (`(tags: string[]) => void`) or `Pick` of an interface, not the whole client. That is interface segregation, structurally.
- **One options object** rather than a long parameter list, so adding a dependency doesn't reorder calls.
- **Over-engineering:** injecting something no test or caller will ever substitute (a pure helper, a constant).

## Extension without editing

Make the variation a value the caller supplies, not a branch inside the code.

- **A list of plugins with optional hooks**, called at fixed points. New behaviour is a new plugin; the core doesn't change.

  ```ts
  type Plugin = {
    name: string;
    received?(context: ReceivedContext): void | Promise<void>;
    returned?(context: ReturnedContext): void | Promise<void>;
  };

  // in the core, at the point each hook is for
  for (const plugin of plugins) await plugin.received?.(context);
  ```

- **A registry keyed by a union**: a record with one entry per member, so adding a member is a type error until its entry exists. Where each entry's types depend on its key, use a mapped type (idioms.md §15).

  ```ts
  type Kind = "text" | "image" | "video";
  const renderers: { [K in Kind]: (block: Blocks[K]) => Output } = { text: renderText, image: renderImage, video: renderVideo };
  ```

- **A function parameter** for a single variation point (a comparator, a formatter, a retry policy).
- **Not a boolean flag** that switches the function's behaviour: two focused functions, or a parameter that is the behaviour.

## Wrapping instead of subclassing

A wrapper takes a function and returns one of the same type, adding behaviour around it (logging, size checks, caching, retries). Wrappers compose, and the wrapped function doesn't know.

```ts
const withTiming = <A extends unknown[], R>(name: string, fn: (...args: A) => Promise<R>, log: (ms: number) => void) =>
  async (...args: A): Promise<R> => {
    const start = performance.now();
    try { return await fn(...args); } finally { log(performance.now() - start); }
  };
```

A wrapper offers everything the wrapped function does: same parameters, same result. Anything it derives goes in a field of its own, not in the wrapped type's.

## Outcomes, failures and partial pages

- **An outcome the caller branches on** is a union named for the function (idioms.md §7). **A fault it can't handle** is thrown.
- **A part that may fail without failing the whole** (one section of a page, one optional data source): run it through a small helper that catches, logs once with the part's name, and returns that part's empty value. The whole still renders, and the failure is visible in the logs.

  ```ts
  export const orEmpty = (logger: Pick<Logger, "error">) =>
    async <T>(part: string, load: () => Promise<T>, empty: T): Promise<T> => {
      try { return await load(); }
      catch (error) { logger.error("Loading {part} failed", { part, error }); return empty; }
    };
  ```

- **Which of the two:** when the caller needs to know what happened (to show a message, or because the outcome carries data such as where it came from), add the failure as a member of the function's union, e.g. `{ status: "unavailable" }`, and log it where it's turned into that member. When the caller only assembles parts and doesn't care why one is missing, use the helper.
- **Log a failure once,** where it's handled, not at every layer it passes through.

## Cancellation

Accept an optional `AbortSignal` in anything that waits on I/O, pass it to every call underneath (`fetch(url, { signal })`), and call `signal?.throwIfAborted()` between steps of a long operation, so an abandoned request stops doing work. A cancellation isn't a failure: let the abort propagate to the caller who asked for it (or return early), and don't log it as an error or turn it into a failure result.

## Module state and bundlers

A module is normally evaluated once, so a module-level instance (`export const cache = createCache()`) is shared by everything that imports it: that's the default, and a variable on `globalThis` would only be a global under another name.

Some toolchains evaluate a module more than once, each time with its own instance: Next.js bundles each server route with its own copy of the modules it imports, and development servers that hot-reload re-run a module on each save (recreating a client or connection pool every time). Only where the project's framework or bundler is known to do this, and an instance must be shared (a cache, a client, a registry):

- keep it on `globalThis` under a distinctive name, created on first use: `globalThis.__appCache ??= createCache()`, with a `declare global` for its type;
- check errors by `name`, not `instanceof`, when they may come from another copy of the class's module (idioms.md §8).

## Patterns, in TypeScript

The Gang of Four patterns name problems worth recognising; their class-based forms are rarely the TypeScript answer. Reach for a pattern when its problem is in front of you, not to use the pattern.

| Pattern | Usual TypeScript form | Notes |
|---|---|---|
| Strategy | a function parameter, or a record of functions | the most common one |
| Factory method, abstract factory | a factory function returning an object | choose the implementation in the composition root |
| Builder | an options object with defaults | a fluent builder only for genuinely staged construction |
| Singleton | a module-level instance | on `globalThis` only where the toolchain duplicates or re-runs modules (above) |
| Adapter | a function mapping one shape to another | keep it at the boundary |
| Decorator | a wrapper function of the same type (above) | |
| Facade | a module exporting a small API over a larger one | |
| Proxy | a wrapper function; the `Proxy` object only for intercepting arbitrary property access | `Proxy` hides behaviour, so usually don't |
| Observer | callbacks, an `EventTarget`, or a hooks list (above) | remove listeners you add |
| Command | a function or closure; a union of action objects when they're serialised or queued | |
| State | a discriminated union and a reducer (idioms.md §3) | |
| Visitor | a record of handlers keyed by `kind`, or a `switch` with an exhaustiveness check (§5) | |
| Iterator | a generator, `for…of` | |
| Template method | a function taking the varying steps as functions | |
| Chain of responsibility | an array of handlers or middleware run in order | |
| Composite | a recursive union type and a recursive function | |
| Mediator, memento, flyweight, prototype, bridge, interpreter | rarely needed in application code | spread syntax and `structuredClone` cover most prototype and memento needs |

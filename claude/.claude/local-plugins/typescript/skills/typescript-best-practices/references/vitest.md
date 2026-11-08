# Vitest

How to apply the `writing-tests` skill with [Vitest](https://vitest.dev). That skill says which tests earn their place; this says how to write and run them with Vitest, and where it surprises people. Facts below were checked against Vitest 5.0 (with Vite 8) by running them; check the installed version's docs (e.g. through Context7) for anything else, rather than working from memory.

## Configuration

```ts
import { defineConfig } from 'vitest/config'

export default defineConfig({
  // Reads tsconfig.json's `paths` (Vite 8; off by default), so aliases aren't copied here
  resolve: { tsconfigPaths: true },
  test: {
    // Tests sit next to the module they test
    include: ['src/**/*.test.{ts,tsx}'],
    environment: 'node',
    // Undo vi.stubEnv, vi.stubGlobal and vi.spyOn before each test, so none leaks into the next
    unstubEnvs: true,
    unstubGlobals: true,
    restoreMocks: true,
    // Runs the `*.test-d.ts` type tests too
    typecheck: { enabled: true }
  }
})
```

- **Path aliases:** `resolve.tsconfigPaths: true` on Vite 8 and later. Before that, the `vite-tsconfig-paths` plugin does it (a dependency to ask about); copying the aliases into `resolve.alias` works, but leaves two sources to keep in step.
- **Type tests (`*.test-d.ts`) don't run unless asked:** `typecheck.enabled` defaults to `false`, and setting only `typecheck.include` changes nothing (its default, `**/*.{test,spec}-d.?(c|m)[jt]s?(x)`, already finds them). Turn it on in the config or with `vitest run --typecheck`, or rely on the project's `tsc` run including the files (a failed `expectTypeOf` is a compile error). Choose one, and check it's in the command CI runs. Vitest runs `tsc` with the project's `tsconfig.json` (or `typecheck.tsconfig`), which must include the type test files, and reports every type error it finds, the source's and (without `skipLibCheck`) the libraries' too, as errors that fail the run; `typecheck.ignoreSourceErrors` turns that off.
- **What the reset options cover:** `restoreMocks` restores the originals of `vi.spyOn` spies only (it doesn't reset a `vi.fn()`); `clearMocks`, on by default in Vitest 5, clears every mock's call history before each test, and `mockReset` resets implementations as well. Nothing resets fake timers: call `vi.useRealTimers()` in an `afterEach`.
- **JSX:** if `tsconfig.json` leaves JSX for a framework to compile (`"jsx": "preserve"`), component tests need Vitest to compile it: `oxc: { jsx: { runtime: 'automatic' } }` on Vite 8 (earlier versions configure esbuild instead).
- **Run once with `vitest run`:** plain `vitest` watches in an interactive terminal. Pass a file path or `-t <name>` to run part of the suite.

## Writing tests

| The skill says | With Vitest |
|---|---|
| One contract, one table-driven test | `it.each([{ value: '0', expected: 5000 }, …])('falls back for $value', ({ value, expected }) => …)`: objects, with `$name` in the title. `test.for` is the same, but passes an array case as one argument instead of spreading it |
| Fakes over mocks | pass a fake in where the code takes its dependencies as parameters (`design.md`, "Dependencies are parameters"); for a global the code calls directly, `vi.stubGlobal('fetch', fake)`; `vi.mock('./module')` last, for a module you can't pass in. `vi.mock` and `vi.hoisted` are hoisted, and Vitest 5 throws if either is inside a function, `describe` or test; `vi.doMock` isn't hoisted |
| Assert what the contract fixes | `expect(value).toMatchObject({ … })` for the fields that matter; `await expect(promise).rejects.toMatchObject({ name: 'TimeoutError' })` for a failure |
| Environment variables | `vi.stubEnv('NAME', value)`, or `undefined` to unset it, reset by `unstubEnvs` |
| Not testing what TypeScript already enforces | that means re-checking a declared type at runtime. A type test (`expectTypeOf`, or `// @ts-expect-error` above a call that must not compile) earns its place where a type is the contract: a generic helper's inferred result, or a constraint callers rely on |
| Logs and telemetry the contract includes | the project's shared helper: `logtape.md` and `opentelemetry.md`, "Testing" |

**Fake timers** (`vi.useFakeTimers()`) fake `setTimeout`, `setInterval`, `setImmediate`, their `clear…` functions and `Date`:

- **`AbortSignal.timeout()` isn't faked:** a signal from it doesn't abort however far fake time is advanced. Test a timeout with real time and a short value (e.g. the timeout set to 20 ms, the test's own to 1 s), or have the code take its signal or timeout as a parameter.
- **A wait inside a promise chain needs the async forms:** `await vi.advanceTimersByTimeAsync(ms)` or `await vi.runAllTimersAsync()`, which settle promises between timers, so a timer set after an `await` is still reached, and the fake `Date` moves with each one. To let every sleep resolve as soon as it's reached, without advancing by hand, use `vi.setTimerTickMode('nextTimerAsync')` (Vitest 4.1 and later).
- **A promise that rejects while timers advance** is reported as an unhandled rejection, even if a later `.rejects` would catch it: attach the assertion first (`const assertion = expect(promise).rejects.toThrow(…)`, then advance, then `await assertion`), or use `nextTimerAsync`.

**State between tests:** each test file gets its own module graph, but tests in one file share it, so a module-level cache or counter carries from one test to the next. Give the module a reset its tests call, or look the state up when it's used (as `opentelemetry.md` does for instruments); `vi.resetModules()` plus a dynamic `import()` re-evaluates a module, but not one imported statically at the top of the file.

## Common mistakes

- **`typecheck.include` without `typecheck.enabled`** (or `--typecheck`), so the type tests never run under Vitest.
- **Fake timers for a request timeout** built on `AbortSignal.timeout()`, which they don't control.
- **`vi.mock` inside a `describe` or test,** which Vitest 5 rejects.
- **Aliases copied into `resolve.alias`** on Vite 8, where `resolve.tsconfigPaths` reads them.
- **Fake timers left on** for the next test, with no `vi.useRealTimers()` in an `afterEach`.

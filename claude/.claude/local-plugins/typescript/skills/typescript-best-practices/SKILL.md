---
name: typescript-best-practices
description: Use when writing, reviewing or refactoring TypeScript, setting up a tsconfig, modelling data types, deciding how a TypeScript module should take its dependencies, report failures or be extended, or setting up or testing logging with LogTape, telemetry with OpenTelemetry's Node SDK, or tests with Vitest.
---

# TypeScript best practices

Write TypeScript the compiler can protect, in the language's own idiom: functions and closures, structural types, unions for state, and classes only where they earn their place. Follow the project's existing conventions first; everything here is the default when it has none.

## How to use this skill

1. **Look at the project first:** its tsconfig, lint rules, and a few modules like the one you're writing. Match their shape: how they take dependencies, report errors, name things and export. If the project uses a framework, check its current docs (e.g. through Context7) for its own TypeScript guidance before applying generic defaults.
2. **Find the situation** in the guide below, and open the reference it names.
3. **Add only what the task needs.** A branded type, a reducer or a guard is worth it where it removes a real risk, not as a template to fill in.

## Decision guide

| Situation | Default | Where |
|---|---|---|
| A module needs collaborators (a client, a logger, a cache) that tests must replace | a factory taking them as one options object; a composition root wires the real ones | design.md, "Dependencies are parameters" |
| Behaviour will vary, or others will add to it | a function parameter, a list of plugins with hooks, or a registry keyed by a union; not a boolean flag | design.md, "Extension without editing" |
| Adding logging, caching or retries around a function | a wrapper function of the same type | design.md, "Wrapping instead of subclassing" |
| A caller must branch on the outcome (found or not, cache or network) | a union named for the function | idioms.md §7 |
| A failure the caller can't handle | throw an `Error` subclass with `name` set, wrapping with `cause` | idioms.md §8, assets/app-error.ts |
| One part may fail without failing the whole (a page section) | catch it in one place, log once, return the part's empty value | design.md, "Outcomes, failures and partial pages" |
| Work waits on I/O and may be abandoned | accept an `AbortSignal` and pass it down | design.md, "Cancellation" |
| An instance must be shared by everything that imports it | a module-level instance; where the toolchain duplicates or re-runs modules (e.g. Next.js server routes, hot reload), the framework's guidance | design.md, "Module state and bundlers"; for Next.js, the `nextjs:nextjs-module-state` skill |
| A Gang of Four pattern comes to mind | its usual TypeScript form | design.md, "Patterns, in TypeScript" |
| Reaching for `any` | `unknown` and narrow it | idioms.md §1 |
| `enum` | a string-literal union or an `as const` object | idioms.md §2 |
| An object can be in contradictory states | a discriminated union | idioms.md §3, assets/discriminated-union.ts |
| Two values of the same primitive type are easily swapped (IDs, units) | a branded type | idioms.md §4, assets/branded-type.ts |
| A `switch` should fail to compile when a case is added | an exhaustiveness check | idioms.md §5 |
| Config or lookup tables lose their literal types | `as const` and `satisfies` | idioms.md §6 |
| `catch (e)` then `e.message` | narrow the `unknown`, log the error itself | idioms.md §8 |
| Data mutated far from where it's made | `readonly` types | idioms.md §9 |
| `null` and `undefined` used interchangeably | one convention, `?.` and `??` | idioms.md §10 |
| A promise nobody awaits | `await` it, or `void` it deliberately | idioms.md §11 |
| A type hand-copied from another | derive it (`Pick`, `Omit`, `Partial`) | idioms.md §12 |
| External input (JSON, request bodies, env) | validate it at the boundary | idioms.md §13, assets/type-guards.ts |
| `interface`, `type` or `class`? | `type` by default | idioms.md §14 |
| Reaching for `as` or `!` | a guard, typed accessor or tighter parameter; a commented cast only at a boundary | idioms.md §15 |
| Logging with LogTape: set-up, log lines, asserting logs in tests | the `instrumentation-and-logging` and `writing-tests` skills, applied with LogTape | references/logtape.md |
| Telemetry with OpenTelemetry's Node SDK: starting it, custom spans and metrics, testing them | the `instrumentation-and-logging` and `writing-tests` skills, applied with the Node SDK | references/opentelemetry.md; in Next.js, the `nextjs:nextjs-instrumentation` skill as well |
| Testing with Vitest: configuration, fakes, timers, type tests | the `writing-tests` skill, applied with Vitest | references/vitest.md |
| Setting up a tsconfig | the template, after the framework's own guidance | assets/tsconfig.template.json |

## Defaults, unless the project differs

These fail silently when skipped, so apply them from the start:

1. `strict: true` and `noImplicitOverride`; `noUncheckedIndexedAccess` for a new project.
2. No `any` outside tests: `unknown` and narrowing.
3. No floating promises: `await`, or an explicit `void` for deliberate fire-and-forget.
4. Exported functions have explicit return types.
5. External data is validated at the boundary. Cast it only when it's trusted to have a documented shape and there's no schema to check it with (§15).
6. No `as` or `!` outside tests except where the types can't say it (a library boundary, a branded type's constructor, inside a guard), each with a one-line comment saying why.

## Files

- `references/idioms.md`: the type-level rules (§1 to §15), each with its reason, an example and when it's over-engineering.
- `references/design.md`: how design principles look in TypeScript: dependencies, extension, wrappers, outcomes, cancellation, module state, and the Gang of Four patterns in TypeScript form. The principles themselves are in the `design-principles` skill.
- `references/logtape.md`: applying the `instrumentation-and-logging` and `writing-tests` skills with LogTape.
- `references/opentelemetry.md`: applying the same two skills with OpenTelemetry's Node SDK.
- `references/vitest.md`: applying the `writing-tests` skill with Vitest.
- `assets/`: starting points to adapt, not copy whole: `tsconfig.template.json`, `app-error.ts`, `discriminated-union.ts`, `branded-type.ts`, `type-guards.ts`.

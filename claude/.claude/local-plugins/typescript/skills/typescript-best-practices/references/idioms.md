# TypeScript Idioms — full reference

Each section: **intent**, a **bad** example, the **idiomatic** version, **notes**, and **when it is over-engineering**.

---

## §1 Prefer `unknown` over `any`; narrow before use

**Intent:** `any` disables the type checker for everything it touches and spreads silently. `unknown` is the type-safe "I don't know yet" — you must narrow it before use, so the check happens at the boundary.

```ts
// ❌ bad — `any` infects every downstream use
function parse(json: string): any {
  return JSON.parse(json);
}
const total = parse(input).order.total * 1.1; // no error, blows up at runtime
```

```ts
// ✅ idiomatic — force a narrowing decision at the boundary
function parse(json: string): unknown {
  return JSON.parse(json);
}

function isOrder(v: unknown): v is { total: number } {
  return typeof v === "object" && v !== null && "total" in v
    && typeof (v as Record<string, unknown>).total === "number";
}

const data = parse(input);
if (!isOrder(data)) throw new TypeError("The order payload has no numeric total");
const total = data.total * 1.1; // safe
```

**Notes:** ban `any` via `@typescript-eslint/no-explicit-any`. For genuinely generic pass-through code use generics (`<T>`), not `any`. `unknown` is correct for `JSON.parse`, `catch` bindings, and external input.

**Over-engineering:** narrowing throwaway script glue, or test fixtures where the shape is asserted right there — `as` is acceptable in tests.

---

## §2 String-literal unions instead of `enum`

**Intent:** TS `enum` emits runtime code, has surprising numeric semantics, and `const enum` breaks under isolated modules / bundlers. A union of string literals is zero-cost, debuggable (the value *is* the label), and JSON-friendly.

```ts
// ❌ bad
enum Status { Active, Disabled }      // values are 0,1 — meaningless in logs/db
```

```ts
// ✅ idiomatic
type Status = "active" | "disabled";

// when you need the runtime list too, derive both from one source:
const STATUSES = ["active", "disabled"] as const;
type Status2 = (typeof STATUSES)[number]; // "active" | "disabled"
```

**Notes:** `as const` array is the single source of truth for "the type" *and* "the iterable list" — no drift. Use an `as const` object map when you need named keys with stable values.

**Over-engineering:** none for app code. `enum` is occasionally justified only when matching an external numeric protocol — even then a `const` map is usually clearer.

---

## §3 Discriminated unions to make illegal states unrepresentable

**Intent:** Optional fields that are "only set sometimes" let contradictory states compile. A tagged union ties each shape to a discriminant so the compiler enforces which fields exist.

```ts
// ❌ bad — loading+error+data all optional; every combination is "valid"
interface State { loading: boolean; data?: User; error?: Error; }
```

```ts
// ✅ idiomatic
type State =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "success"; data: User }
  | { status: "error"; error: Error };

function render(s: State) {
  switch (s.status) {
    case "idle": return "—";
    case "loading": return "spinner";
    case "success": return s.data.name;   // s.data exists only here
    case "error": return s.error.message; // s.error exists only here
  }
}
```

See `assets/discriminated-union.ts`. Pair with §5 for exhaustiveness.

**Over-engineering:** a struct with independent optional fields that genuinely *are* independent (e.g. an address with optional `line2`) — that is not a state machine; leave it.

---

## §4 Branded (nominal) types for un-swappable primitives

**Intent:** TypeScript is structural: `userId: string` and `orderId: string` are interchangeable, so they get swapped at call sites. A brand adds a phantom tag that only a smart constructor can produce.

```ts
type UserId = string & { readonly __brand: "UserId" };
const UserId = (raw: string): UserId => {
  if (!raw) throw new Error("empty UserId");
  return raw as UserId;
};

function getUser(id: UserId) { /* ... */ }
getUser("o_123");            // ❌ compile error — plain string
getUser(UserId("u_123"));    // ✅
```

Full helper in `assets/branded-type.ts`.

**Over-engineering:** branding every string. Reserve it for IDs, money, units, and other primitives whose accidental mix-up is a real, costly bug class.

---

## §5 Exhaustiveness checking with `never`

**Intent:** Make the compiler fail when a new union member is added but a `switch`/`if` chain isn't updated.

```ts
function assertNever(x: never): never {
  throw new Error(`Unhandled variant: ${JSON.stringify(x)}`);
}

function area(s: Shape): number {
  switch (s.kind) {
    case "circle": return Math.PI * s.r ** 2;
    case "square": return s.side ** 2;
    default: return assertNever(s); // adding "triangle" → compile error here
  }
}
```

**Notes:** prefer `switch` returning a value so every arm must produce the result type. `assertNever` is also a runtime guard against malformed data.

**Over-engineering:** never; this is cheap insurance and belongs on every exhaustive union handler.

---

## §6 `as const` and `satisfies` for config/literals

**Intent:** `satisfies` validates a value against a type *without widening* it — you keep the precise literal types and still get the constraint check.

```ts
// ❌ bad — `: Config` widens `port` to number, loses key autocomplete
const config: Record<string, number> = { port: 8080 };

// ✅ idiomatic
const config = {
  port: 8080,
  host: "localhost",
} satisfies Record<string, string | number>;

config.port;  // type 8080 (literal), checked, autocompleted
```

**Notes:** `as const` deep-freezes types to literals & `readonly`; combine with `satisfies` to keep literals *and* enforce a shape.

**Over-engineering:** plain mutable locals don't need either.

---

## §7 Expected outcomes are a union; faults are thrown

**Intent:** follow the project's own error style first. Where it has none: an outcome the caller has to branch on ("not found", "rejected input", "served from cache") belongs in the return type, so the compiler makes every caller handle it. A fault the caller can't do anything about (a bug, missing configuration, an unreachable service with nothing to fall back to) is thrown, and caught where it can be handled or reported.

```ts
type Lookup =
  | { found: true; user: User }
  | { found: false; reason: "missing" | "disabled" };

const lookup = await findUser(id);
if (!lookup.found) return notFound(lookup.reason); // the compiler forces this branch
greet(lookup.user);
```

**Notes:** give each function its own union, with fields named for what it returns, rather than a shared generic `Result<T, E>` with combinators (`map`, `flatMap`, `unwrap`): that's a library-style abstraction to adopt only if the project already uses one.

**Over-engineering:** threading a union through layers that only pass it on. Throw instead, and catch where it's handled.

---

## §8 Type the `catch`, narrow the error

**Intent:** under `useUnknownInCatchVariables` (on with `strict`) the catch binding is `unknown`. Don't cast it: narrow it, handle what you can, and rethrow the rest.

```ts
try {
  await save(draft);
} catch (error) {
  if (error instanceof QuotaError) return showQuotaMessage();
  logger.error("Saving the draft failed", { error }); // the error itself: its type, message and stack
  throw error;
}
```

**Notes:**

- An error class is a small `Error` subclass that sets `name`; when it wraps another error, pass `{ cause }` so the original isn't lost. See `assets/app-error.ts`.
- `instanceof` compares class identity, so it fails when the error comes from another copy of the class's module (some bundlers include a module once per entry point). Where that can happen, check `error.name` instead.
- Log the error object, not `error.message`, which drops its type and stack.

**Over-engineering:** none. Swallowing errors, or `catch (e: any)`, is the anti-pattern.

---

## §9 Immutability by default

**Intent:** Shared mutable objects cause action-at-a-distance bugs. Make the type say "you may not mutate this".

```ts
function totalize(items: readonly LineItem[]): Money { /* can't push/splice */ }

interface User {
  readonly id: UserId;
  readonly email: Email; // identity fields never reassigned
}

const DEFAULTS = Object.freeze({ retries: 3 }); // runtime + compile guard
```

**Notes:** `readonly` is compile-time only; `Object.freeze` adds a runtime guarantee for true constants. Prefer returning new objects (`{...o, x}`) over in-place mutation in domain code.

**Over-engineering:** deep-freezing large hot-path data structures, or making every local `readonly`. Apply at module/domain boundaries.

---

## §10 One null convention; lean on `?.` and `??`

**Intent:** Mixing `null` and `undefined` doubles every absence check. Pick one for "absent" (TS leans `undefined`; APIs/DBs often `null`) and normalize at the boundary.

```ts
const name = user.profile?.displayName ?? "Anonymous"; // not `|| ` — keeps "" / 0
function find(id: Id): User | undefined { /* absence is undefined */ }
```

**Notes:** `??` only falls back on `null`/`undefined`; `||` also falls back on `""`, `0`, `false` — usually a bug. Enable `strictNullChecks` (part of `strict`).

**Over-engineering:** none; this is a baseline convention.

---

## §11 No floating promises

**Intent:** An un-awaited promise that rejects becomes an unhandled rejection and the error is invisible. Every promise is awaited, returned, or explicitly `void`-ed with a comment.

```ts
await sendEmail(u);                       // ✅ awaited
return repo.save(o);                      // ✅ returned
void analytics.track("evt").catch(noop);  // ✅ deliberate fire-and-forget

const [a, b] = await Promise.all([fa(), fb()]); // concurrent, not sequential awaits
```

**Notes:** enable `@typescript-eslint/no-floating-promises`. Don't `await` in a loop when calls are independent — use `Promise.all`.

**Over-engineering:** none.

---

## §12 Derive types with utility types

**Intent:** Hand-copied object shapes drift from their source. Derive them.

```ts
type User = { id: UserId; email: Email; passwordHash: string };

type PublicUser = Omit<User, "passwordHash">;
type UserPatch  = Partial<Pick<User, "email">>;
type UsersById  = Record<UserId, User>;
type CreateUser = Omit<User, "id">;
```

**Notes:** also `Parameters`, `ReturnType`, `Awaited`, `NonNullable`, `Exclude`/`Extract`. Derive *down* from the canonical type; don't build the canonical type up from fragments.

**Over-engineering:** chains so deep (`Partial<Pick<Omit<...>>>`) that a named explicit type would read better — name it.

---

## §13 Validate at the boundary; never cast external data

**Intent:** `JSON.parse`, `req.body`, env vars, DB rows are `unknown`. A cast (`as User`) is a lie the compiler believes. Validate, then the type is *earned*.

```ts
function assertIsCreateUser(v: unknown): asserts v is CreateUser {
  if (typeof v !== "object" || v === null) throw new TypeError("not an object");
  const o = v as Record<string, unknown>; // inside the guard: reading fields of a checked object
  if (typeof o.email !== "string") throw new TypeError("email required");
}
```

**Notes:** for non-trivial schemas, use the runtime validation library the project already has, ideally one that infers the static type from the schema so the two can't drift; don't add one without asking. Hand-written guards (see `assets/type-guards.ts`) are fine for small or internal shapes.

**Over-engineering:** validating data you fully control and that never crosses a process/IO boundary.

---

## §14 `interface` vs `type` vs `class`

- **`type`:** the default for unions, intersections, mapped and conditional types, function types, and most object shapes.
- **`interface`:** an object contract that something implements or that benefits from declaration merging (rare in application code), e.g. a plugin's shape.
- **`class`:** only where it earns its place: an `Error` subclass, an interface a library requires you to implement, or a project that already uses classes. Anything with dependencies and behaviour is otherwise a factory function returning an object (`references/design.md`).

```ts
type Lookup = Found | Missing;                                   // union → type
interface Plugin { name: string; received?(c: Context): void; }  // contract → interface
class QuotaError extends Error { override name = "QuotaError"; } // error → class
```

**Over-engineering:** a class with only public fields and no behaviour (a `type`), or a class wrapping one function (the function).

---

## §15 Casts (`as`) and non-null assertions (`!`) only where the types can't say it

**Intent:** a cast or `!` tells the compiler "trust me" and turns off the check at exactly the point where the types disagree, so a later change that makes the claim false compiles cleanly. Most casts are a sign the types could say it: a guard, a typed accessor or a better parameter type removes the disagreement instead of hiding it.

```ts
// ❌ bad — widening the list to call includes, and asserting a key exists
const SIZES = ["s", "m", "l"] as const;
type Size = (typeof SIZES)[number];
if ((SIZES as readonly string[]).includes(input)) use(input as Size);
const label = LABELS[key as keyof typeof LABELS]!;

// ✅ idiomatic — a reusable guard narrows, and an own-key check narrows the key
const isOneOf = <T extends string>(list: readonly T[], value: unknown): value is T =>
  typeof value === "string" && list.some((member) => member === value);
if (isOneOf(SIZES, input)) use(input);

const hasKey = <T extends object>(obj: T, key: PropertyKey): key is keyof T => Object.hasOwn(obj, key);
if (hasKey(LABELS, key)) render(LABELS[key]);
```

**Where a cast is right:**

- **A library boundary:** one library's type for another's data, or data trusted to have a documented shape (a response the API's docs define), when there's no schema to validate it with (§13).
- **A branded type's smart constructor,** once, after it has validated the value (`assets/branded-type.ts`): the brand exists only in the type, so nothing else can create one.
- **Inside a guard or a type-level builder,** once, where the narrowing itself can't be expressed (e.g. reading the fields of an `unknown` already checked to be an object, §13).
- **Tests and throwaway scripts,** where the shape is asserted right there.

Each cast in application code gets a one-line comment saying why the types can't say it. If you can't write that comment, there's a better fix.

**Instead of a cast, reach for:**

| Situation | Fix |
|---|---|
| Checking a value is one of a list | a guard like `isOneOf` |
| Indexing an object by a string | an own-key guard like `hasKey`, or a `Map` |
| `!` on a value you know is set | narrow it (`if (!x) throw …`), or make the type say it's set (a required parameter, a non-optional field) |
| A registry indexed by a union, whose entries' types depend on the key | a mapped type indexed through a type parameter (TypeScript's pattern for correlated unions: `function run<K extends Kind>(kind: K, value: Values[K]) { return handlers[kind](value) }` with `handlers: { [K in Kind]: (v: Values[K]) => R }`) |
| A function that receives a wider type than it needs | tighten the parameter type, so callers prove it |
| `as const` | fine: it narrows rather than asserts |

**Notes:** ban the unchecked forms in lint: `@typescript-eslint/no-explicit-any`, `consistent-type-assertions` (e.g. `objectLiteralTypeAssertions: "never"`), `no-non-null-assertion` and `no-unnecessary-type-assertion`, relaxed for tests. Prefer the project's existing guards over writing new ones: search for `is…`/`has…` helpers first.

**Over-engineering:** a guard written to avoid one cast at a genuine library boundary. The commented cast is clearer.

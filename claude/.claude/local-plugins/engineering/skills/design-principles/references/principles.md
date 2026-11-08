# The principles in detail

Each principle: what it's for, the smell that calls for it, the fix in words, and when applying it is over-engineering. Code is deliberately left to the language skills: the fix looks different in each language (see "How each principle looks" in `SKILL.md`).

## Single responsibility

**Intent:** a module (class, file, package) has one reason to change: one actor or concern whose needs drive its edits.

**Smell:** one module changes for unrelated reasons, e.g. a pricing rule, an email template and a database schema all edited in the same file; a description that needs "and".

**Fix:** split by reason to change, not by size. Pull each concern into its own module and have a thin coordinator call them in order.

**Over-engineering when:** the split leaves single-line modules with more wiring than logic, or separates things that always change together (that's cohesion, below).

## Open for extension, closed for modification

**Intent:** adding a variant (a payment method, a notification channel, a file format) means adding code next to the existing variants, not editing a central switch that every variant passes through.

**Smell:** a growing `switch` or `if` chain on a type or name; every new variant touches the same function; type checks (`instanceof`, `kind ===`) decide behaviour in several places.

**Fix:** make the variation a value the caller or a registry supplies: one implementation per variant behind a shared contract, selected by name, with the shared flow written once. When the set of variants is closed and small, a union with an exhaustive check is the simpler form: adding a member is a compile error until every place handles it.

**Over-engineering when:** there are two variants and no third in sight; an extension point no one will extend.

## Substitutability (Liskov)

**Intent:** any implementation of a contract can stand in for any other without the caller noticing: same inputs accepted, same promises kept, no surprise exceptions.

**Smell:** an implementation throws "not supported" or silently does nothing for part of its contract; callers check which implementation they have before calling it.

**Fix:** narrow the contract to what every implementation can honour, and split out the extra capability as its own contract. Prefer composition to inheritance when a subtype would have to disable behaviour it inherited.

**Over-engineering when:** there's only one implementation and no plan for another.

## Interface segregation

**Intent:** a caller depends only on the operations it uses, so changes to the others can't affect it.

**Smell:** implementers stub members they don't need; a function takes a whole client or service to call one method; tests must fake a large surface to exercise a small path.

**Fix:** depend on the narrowest contract that works: a role interface with the one or two operations needed, or a single function.

**Over-engineering when:** each caller gets its own bespoke interface for operations that always travel together.

## Dependency inversion

**Intent:** the code that holds the policy (business rules) doesn't depend on the details (databases, HTTP clients, SDKs, the clock, the environment). It states what it needs, and the details are passed in from outside.

**Smell:** business logic constructs or imports a concrete client, reads environment variables or the clock directly; unit tests need a real network, database or time.

**Fix:** declare what the logic needs as a contract it owns (an interface or a function type), pass the implementations in, and wire the real ones in one composition root (the one place that builds the application's objects). Tests pass fakes. Where a vendor's API can't be substituted (static calls, sealed types), put a thin adapter you own around it and keep the rules out of the adapter, in code that receives it: the rules are then testable with a fake adapter, and the adapter is too small to need a unit test.

**Over-engineering when:** abstracting something no caller or test will ever substitute (a pure helper, a constant), or wrapping a library in an interface with exactly its own shape "in case".

## Coupling, measured by connascence

**Intent:** minimise what one module must know about another so a change stays local. Connascence makes coupling concrete: two pieces of code are connascent if changing one forces a change in the other.

From weakest to strongest: **name** (they agree on an identifier), **type**, **meaning** (they agree that `-1` means "not found"), **position** (they agree on argument order), **algorithm** (both must compute a hash the same way), **timing** (one must run before the other). Weaken the form, or shrink its distance to one module.

**Smell:** editing one function forces edits elsewhere; arguments must be passed in a magic order; two modules share an undocumented convention.

**Fix:** named arguments or an options object instead of position; named values or types instead of magic numbers; one module owning a shared algorithm and exposing it, never two copies across a boundary.

**Over-engineering when:** the two modules really are one concept; an interface between them just to "decouple" adds an indirection with one implementation. Some coupling is the design.

## Cohesion

**Intent:** keep together what changes together and is used together.

**Smell:** a "utils" or "helpers" module whose functions share nothing but the file; a feature whose code is scattered across layers, so one change touches many folders.

**Fix:** group by what the code is about. Move each function next to the code it serves, or to the most general module it fits if callers unrelated to that code would use it too.

**Over-engineering when:** a module is split so finely that understanding one behaviour means opening many files.

## DRY

**Intent:** each piece of knowledge (a business rule, a threshold, a format) has one authoritative home.

**Smell:** the same rule written in several places, so changing it means finding them all.

**Fix:** one named definition, used everywhere the rule applies. Derive what you can from it (types from a schema, labels from a list) rather than keeping copies in step.

**The counter-rule (false DRY):** code that looks the same but encodes different decisions stays separate. A free-trial rule and a legal-age rule may share a condition today; merging them means changing one breaks the other. Wait for the third occurrence, and a proven shared concept, before extracting.

**Over-engineering when:** deduplicating incidental similarity.

## YAGNI

**Intent:** build for the requirement in front of you.

**Smell:** options, flags, extension points or abstractions "for later" with one caller; configuration nobody sets.

**Fix:** delete or inline them, and add them back when a real requirement arrives. Code written for a guessed requirement is usually wrong for the real one.

**Over-engineering when:** n/a. The counterweight is cost: when adding something later would mean a data migration or a breaking change to a published API, decide now.

## KISS

**Intent:** the simplest design that works. Complexity must be earned by a real requirement.

**Smell:** a generic layer, metaprogramming or clever type-level code that few people on the team can explain; indirection that doesn't buy anything.

**Fix:** the plain version. If it falls short, explain why before adding the clever one.

**Over-engineering when:** "simple" becomes a long copy-pasted `switch` that a small abstraction would make clearer. Simplicity is fewest concepts, not fewest lines.

## Separation of concerns

**Intent:** transport (HTTP, queues, UI), policy (business rules) and storage live apart and can change apart.

**Smell:** one function parses the request, applies business rules, queries the database and formats the response.

**Fix:** a thin outer layer that translates in and out, policy in the middle that knows nothing of transport or storage, and storage behind contracts the policy owns (dependency inversion).

**Over-engineering when:** a small script or a single endpoint gets three layers and their wiring.

## Encapsulation

**Intent:** hide how something is represented; expose what it's for.

**Smell:** callers reach into internal state and mutate it; a representation change (a list to a map, cents to a money type) breaks code far away.

**Fix:** expose operations and read-only views, not mutable internals. In object-oriented code that's private state behind methods; in functional code, state held in a closure or module and exposed through functions, with read-only types.

**Over-engineering when:** wrapping plain data that is just data (a request body, a view model) in accessors.

## Tell, don't ask

**Intent:** the code that owns the data makes the decisions about it, rather than every caller reading the state and deciding for itself.

**Smell:** the same "read the fields, decide, write back" logic repeated at several call sites.

**Fix:** move the decision next to the data: a method on the object, or a function in the module that owns the data, which callers ask to decide.

**Over-engineering when:** applied to data that's legitimately read for display or serialisation (view models, API responses). Querying state to show it is fine; deciding domain behaviour from outside is the smell.

## Law of Demeter

**Intent:** talk to your immediate collaborators, not to their collaborators.

**Smell:** chains reaching through the object graph (`order.customer().address().postcode()`), so a change deep in the graph breaks callers far away.

**Fix:** ask the nearest collaborator for what you actually need, or pass that value in directly.

**Over-engineering when:** applied to fluent APIs and plain data navigation (`config.server.port`), where the chain is the design.

## Composition over inheritance

**Intent:** assemble behaviour from small parts; reserve inheritance for genuine "is a substitutable kind of".

**Smell:** a subtype inherits behaviour it has to disable; deep hierarchies where a change to a base class ripples unpredictably; a subclass created to vary one step.

**Fix:** pass the varying part in (delegation, a strategy, a function parameter) and wrap rather than extend.

**Over-engineering when:** a shallow, stable hierarchy (often a framework's own extension point) already expresses the relationship.

## Command–query separation

**Intent:** a call either changes state or answers a question, not both, so reading never has hidden effects.

**Smell:** a getter that also writes or caches visibly; a `check` that also fixes; a function named like a question that mutates.

**Fix:** split into a command and a query. Where returning the result of a write is the convention (an inserted row's ID, a stack's `pop`), name it as a command.

**Over-engineering when:** splitting an atomic operation that has to read and write together.

## Least astonishment

**Intent:** behaviour matches the name and what a caller would reasonably expect.

**Smell:** `getUser` creates a user when it's missing; a boolean parameter switches what the function does (`render(true)`); defaults that surprise.

**Fix:** a name that says everything the function does, or split it. Replace a behaviour-switching flag with two focused functions, or a parameter that is the behaviour itself.

**Over-engineering when:** n/a; but beware renaming established, widely used APIs for purity.

## Fail fast

**Intent:** reject invalid input where it enters, loudly, before it spreads.

**Smell:** bad data detected several layers in, or not at all; defaults that hide missing configuration.

**Fix:** validate at the boundary (requests, files, environment, external APIs) with the project's existing validation tools, check required configuration at startup, and model states so invalid ones can't be represented.

**Over-engineering when:** re-validating data already checked at the boundary on every internal call. For a failure the system can survive (one optional section of a page), degrade gracefully and log it instead of failing the whole.

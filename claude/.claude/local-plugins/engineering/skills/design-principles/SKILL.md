---
name: design-principles
description: Use when designing or refactoring modules, reviewing code for coupling, duplication, rigidity or leaky abstractions, deciding whether an abstraction or pattern earns its keep, or asking which design principle applies, in any language.
---

# Design principles

## Overview

Design principles exist so the next change is cheap and local. They hold in any language, but how they look doesn't: in an object-oriented language they're interfaces, constructor injection and polymorphism; in a functional-first one they're function types, parameters, closures and unions. Apply each principle through the idioms of the language and the shape of the project in front of you, never by importing another language's patterns.

## How to use this skill

1. **Look at the project first:** find modules doing the same kind of job and match how they take dependencies, extend behaviour and report failure. The project's established shape wins over a textbook form.
2. **Name the pain:** match what you see in the decision guide below to a principle. No pain, no principle: these respond to change pressure that exists, not to a checklist.
3. **Read the principle** in `references/principles.md`: its intent, the smell, the fix, and when it's over-engineering.
4. **Apply it in the language's idiom.** "How each principle looks" below gives the usual form in object-oriented and functional-first code; the language's own skill has the code (e.g. `typescript-best-practices`, its `references/design.md`).
5. **Make the smallest change that removes the pain.** Principles trade off against each other (DRY against coupling, YAGNI against extensibility): resolve the conflict in favour of the code that's cheapest to change now.

## The principles

| Principle | Intent |
|---|---|
| **Single responsibility** | A module has one reason to change: you can describe it in one sentence without "and". |
| **Open for extension, closed for modification** | New variants are added alongside, not by editing a growing `switch`. |
| **Substitutability (Liskov)** | Every implementation of a contract honours it, so callers never check which one they have. |
| **Interface segregation** | Callers depend only on what they use. |
| **Dependency inversion** | Policy depends on contracts it owns; the concrete clients are passed in from outside. |
| **Coupling, measured by connascence** | Minimise what one module must know about another; weaken the form or shorten the distance. |
| **Cohesion** | Keep together what changes together and is used together. |
| **DRY** | Each piece of knowledge has one authoritative home (knowledge, not similar-looking code). |
| **YAGNI** | Build for the requirement you have, not the one you imagine. |
| **KISS** | The simplest design that works; complexity has to be earned. |
| **Separation of concerns** | Transport, policy and storage live apart and can change apart. |
| **Encapsulation** | Hide representation; expose intent. |
| **Tell, don't ask** | The code that owns the data makes the decisions about it. |
| **Law of Demeter** | Talk to your immediate collaborators, not their collaborators. |
| **Composition over inheritance** | Assemble behaviour from parts; inherit only for true substitutability. |
| **Command–query separation** | A call either changes state or answers a question, not both. |
| **Least astonishment** | Behaviour matches the name and the caller's reasonable expectation. |
| **Fail fast** | Reject invalid input at the boundary, loudly, before it spreads. |

## Decision guide

| You notice | Principle |
|---|---|
| A module changes for unrelated reasons (I/O, formatting, business rules) | single responsibility, separation of concerns |
| Adding a variant means editing a growing `switch` or `if` chain | open for extension |
| An implementation throws "not supported", or callers check which one they have | substitutability, composition over inheritance |
| Implementers stub out members they don't need, or a function takes a whole client to call one method | interface segregation |
| Business logic constructs or imports a concrete client (database, HTTP, SDK, clock, environment) | dependency inversion |
| Unit tests need a real database, network or clock | dependency inversion |
| Changing one module forces edits in several others; arguments must come in a magic order | coupling |
| A file groups unrelated helpers used by different callers | cohesion |
| The same business rule is written in several places | DRY |
| Two pieces of code look alike but model different decisions | stop: false DRY (principles.md) |
| An abstraction, option or extension point exists "for later", with one user | YAGNI |
| A clever generic or metaprogramming layer few can explain | KISS |
| Callers read an object's state, decide, then write it back | tell, don't ask; encapsulation |
| `a.b().c().d()` chains reach through the object graph | Law of Demeter |
| A boolean parameter switches what a function does | least astonishment, single responsibility |
| A read has side effects, or a write returns data callers come to rely on | command–query separation |
| Bad data is noticed far from where it entered | fail fast |

## How each principle looks

The same principle, in the two common styles. Use the one the language and project already follow.

| Principle | Object-oriented (e.g. C#, Java) | Functional-first (e.g. TypeScript, JavaScript) |
|---|---|---|
| Single responsibility | a class with one reason to change | a module with one reason to change |
| Dependency inversion | interfaces injected through constructors, wired by a DI container or composition root | collaborators passed as parameters or an options object to a factory, wired in one composition root |
| Interface segregation | small role interfaces | narrow function types, or a picked subset of a type |
| Open for extension | polymorphism, or a strategy interface | a function parameter, a registry keyed by a closed set of names, a list of plugins with hooks, or a union with an exhaustive `switch` |
| Substitutability | a subclass or implementation honours the base contract | every function of a type, and every union member's handler, honours the same contract |
| Composition | delegation to injected objects; decorators wrapping an interface | function composition; wrappers returning a function of the same type |
| Encapsulation | private fields behind methods | closures, module-private functions, read-only types |
| Tell, don't ask | methods on the object that owns the state | functions in the module that owns the data, which callers ask to decide |
| Fail fast | guard clauses and validation in constructors | validation at the boundary, and types that can't represent invalid states |

Named patterns follow the same rule: a pattern names a problem worth recognising, and its classic class-based form is one language's answer. The language skill gives the idiomatic form (in TypeScript, a strategy is a function parameter and a visitor is a record of handlers).

## When it's over-engineering

- **One implementation, no test need:** an interface, injection point or plugin system with a single user is YAGNI. Add the seam when the second implementation or a real test needs it.
- **A rule followed past its purpose:** splitting a cohesive module to satisfy single responsibility, or merging two similar functions that encode different decisions to satisfy DRY.
- **A pattern for its own sake:** if you can't name the change it makes cheaper, don't add it.

## Common mistakes

- **Carrying one language's form into another,** e.g. class hierarchies and constructor injection in functional-first TypeScript, or loose functions where a C# codebase uses injected services.
- **Applying principles preemptively,** an interface per class, a factory per type, "just in case".
- **False DRY:** coupling two things that only look alike, so a change to one breaks the other.
- **Fixing a boolean flag with another option:** split the behaviour into two focused functions, or make the parameter the behaviour itself.
- **Adding a dependency to illustrate a principle** (a validation or DI library) the project doesn't already use: ask first.

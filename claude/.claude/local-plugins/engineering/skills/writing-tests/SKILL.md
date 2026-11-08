---
name: writing-tests
description: Use when writing, changing or reviewing automated tests, including during TDD, when deciding whether a test is worth keeping, or when a task that added tests is finishing.
---

# Writing tests

## Overview

Every test is code someone maintains for as long as the code it tests lives, so each one has to earn its place. A good suite fails when behaviour someone relies on breaks, and stays quiet through refactors that don't change that behaviour. Too many low-value tests is a smell: they slow every change and teach people to "just update the test".

If the project has its own version of this skill, use that one: it adds the project's specifics to this.

## The yardstick

A test is worth keeping if **both** are true:

1. It guards behaviour someone relies on, which could plausibly break in future.
2. When it fails, the right response is usually to fix the code, not to update the test.

If the usual response to its failure would be "update the test", it's noise.

| Keep | Don't keep |
|---|---|
| A module's contract at its boundary: what callers get back, including errors and edge cases | Tests that restate the implementation, e.g. asserting which mocks were called in which order |
| Logic with real edge cases (parsing, path rewriting, walking nested data) | A one-off bug that the code's structure now makes impossible |
| Security-relevant behaviour (escaping, URL safety, signatures, access checks) | Library or framework behaviour |
| A regression in a genuinely fragile area that could recur | What the type checker already guarantees, in a typed language |
| | Large snapshots nobody reads |

## How to write them

- **Test first.** Write the test, watch it fail for the reason you expect, then write the code (`superpowers:test-driven-development` if available). For code that already exists, check each test can fail: break the code briefly in the way the test guards against, watch the test fail, and put the code back.
- **If the test runner can't run** (not installed, or needing something you can't start), say so in your report rather than claiming the tests pass, and don't install anything without asking.
- **Test through the public interface.** Call what callers call and assert what they get back. Don't export a private function just to test it; test it through the function that uses it.
- **Assert outcomes, not calls.** Prefer "returns an empty list and logs an error" to "called `listings` once with `'abc'`". Assert a call only when the call *is* the behaviour (a request that must not be sent, a cost that must not be paid, an email that must go out).
- **Assert only what the contract fixes.** If it says "logged with the key and the error" but not the property names, check the values are there, not what they're called, so a rename doesn't fail the test.
- **One contract, one test.** Fold cases of the same rule into one table-driven test rather than a test per input; name the test by the rule it guards ("a failing source gives its empty value and is logged"), not by the input.
- **Fakes over mocks.** Hand-written fakes with real behaviour (an in-memory store, a source that throws) read better and survive refactors that mocks don't.
- **Cover the obvious neighbouring case.** If you test "a new item is created", ask whether "an existing item is replaced" is the case that will actually break.
- **Tests don't prove a UI works.** For a UI, editor flow or integration change, also run the real thing (the app, the build, the editor) before calling it done.

## Scaffolding tests

Tests written during TDD to drive out a detail, or to confirm a fix while developing, are scaffolding. Once the behaviour is covered by a contract-level test, delete them or fold them into it. At the end of a task, review every test it added or changed against the yardstick, and say in the report which were kept, removed or merged, and why.

## In the project

Find these before writing tests; the project's instructions, README and existing tests usually show them:

- **The runner, its command and the file convention:** next to the module or in a tests folder, and, where the project has them, how type-level and component tests are named and run.
- **Shared helpers and fixtures,** and how fixtures are made. A script that captures them from a live system may need the person you're working with to run it or agree to it.
- **How logs are asserted,** if they are.
- **Anything exempt** from the yardstick, such as code that's due to be deleted.
## Common mistakes

- **A test per input** where one table-driven test states the rule.
- **Asserting a mock's calls** for behaviour visible in the return value.
- **Keeping TDD scaffolding** because it passes.
- **Testing what TypeScript already enforces,** e.g. that a function rejects a wrong type.
- **A test that passes first time** without having been seen to fail: check it can fail (break the code briefly) before trusting it.

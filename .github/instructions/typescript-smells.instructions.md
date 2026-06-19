---
applyTo: "**/*.ts,**/*.tsx,**/*.mts,**/*.cts,**/*.js,**/*.jsx,**/*.mjs,**/*.cjs"
---

# TypeScript / JavaScript Recurring Code Smells Instructions

<!-- read-receipt-token: 97382033 -->

> **Scope:** loaded on TS / JS / React / Node files. Contains TS/JS-specific recurring code smells (React, async, Azure Functions, general TS) to audit during self-review and panel review. Naming / formatting / imports / style live in the sibling `javascript-typescript.instructions.md` (same `applyTo` glob). Industry-standard baselines - extend with project-specific conventions as they emerge.

---
## TypeScript / JavaScript recurring code smells

These are an advisory audit lens for self-review + panel review: patterns to grep / spot, not mechanically verified. No gate confirms any of these is absent; the post-code-change recurring-pattern sweep is self-attested.

### React / hooks
- **Missing or incorrect `useEffect` dependency array - audit every effect.** A deps array that omits a reactive value the body reads captures a stale closure; an EMPTY array `[]` runs the effect only once (so it too can capture stale props/state); an OMITTED array (no second argument) runs after every render and loops when the effect updates state it depends on. Spot: for every `useEffect`/`useMemo`/`useCallback`, confirm the deps array lists exactly the reactive values the body reads.
- **Hooks called conditionally or inside loops/callbacks.** Rules-of-hooks require hooks at the top level of a component / custom hook, in the same order every render. Grep for a hook inside `if (...)`, inside `.map(...)`, or after an early `return`.
- **List rendered without a stable `key` (or index-as-key on a reorderable list).** `key={index}` on a list that can reorder / insert / delete causes wrong state reuse and subtle UI bugs. Spot `.map((item, i) => <X key={i} ... />)`; prefer a stable id.
- **Direct state mutation instead of an immutable update.** `state.items.push(x)` or `obj.field = y` followed by `setState(state)` does not trigger a re-render and can corrupt shared references. Look for mutation of a value sourced from `useState`/props; require a fresh object / array (`[...prev, x]`).
- **Missing effect cleanup for subscriptions / timers / listeners.** An effect that calls `addEventListener` / `setInterval` / `subscribe` without returning a cleanup leaks and double-binds across renders. Confirm each such effect returns a teardown function.
- **Expensive work or fresh literals not memoized, causing re-render storms.** A new object / array / function literal passed as a prop on every render defeats `React.memo` and re-triggers child effects. Spot inline `{...}` / `() => ...` props on hot components; consider `useMemo` / `useCallback`.
- **Derived state stored in `useState` instead of computed during render.** Duplicating a value that can be computed from props/state into its own state creates sync bugs. If a `useState` is only ever set from other state (often via an effect), compute it inline instead.

### Async / promises
- **Floating promise (un-awaited async call with no `.catch`).** An async call whose result is discarded swallows rejections and races. Grep for calls to `async` functions not preceded by `await` / `return` / `void` and not chained with `.catch`.
- **`await` in a loop where `Promise.all` fits.** Sequential `for (...) { await f(x) }` over independent work serializes needlessly. Spot `await` inside `for` / `while` / `for..of`; if the iterations are independent, prefer `Promise.all(items.map(f))`.
- **Missing `try/catch` around `await` in an event handler or top-level path.** An unhandled rejection in a handler logs nothing useful or crashes. Confirm awaited calls in handlers have a rejection path.
- **`async` passed where a void callback is expected.** Passing an `async` function to `useEffect`, `Array.forEach`, or an event prop returns an ignored Promise (rejections lost; the `useEffect` cleanup contract is broken). Spot `useEffect(async () => ...)` and `forEach(async ...)`.

### Azure Functions
- **Trigger payload used without input validation.** HTTP / queue / blob trigger bodies are untrusted; using `req.body.x` or `JSON.parse` output directly without a shape check is a smell. Validate / parse at the boundary.
- **Output binding not awaited or returned.** A function that sets `context.bindings.out` or returns a binding object but exits early (or forgets to `return`) silently drops the output. Confirm the binding is set / returned on every path.
- **Secrets / connection strings read from code instead of app settings.** Hardcoded keys and connection strings belong in `process.env` / app settings / Key Vault. Grep for literal connection-string or key patterns.
- **Handler without try/catch leaks a 500 + stack.** An unguarded throw surfaces an unhandled 500 with a leaked stack trace to the caller. Wrap the handler body and return a sanitized error.
- **`console.log` instead of the Functions `context` logger.** `console.log` bypasses the platform's structured logging and correlation. Prefer `context.log`.
- **Long-running or blocking work on a synchronous path.** CPU-bound or blocking I/O in a trigger handler ties up the worker. Flag obviously heavy synchronous work for offloading.

### General TypeScript
- **`any` used as an escape hatch where the type is knowable.** `any` disables checking and spreads through call sites. Grep for `: any`, `as any`, `<any>`; prefer a real type, `unknown` + narrowing, or a generic.
- **Non-null assertion `!` masking a genuinely nullable value.** `x!.foo` asserts away a real nullable and crashes at runtime. Treat each `!` as suspect; prefer a guard or optional chaining.
- **`==` / `!=` instead of `===` / `!==`.** Loose equality coerces (`0 == ''`, `null == undefined`). Grep for ` == ` / ` != ` (allow the deliberate `== null` idiom only where the project documents it).
- **Unvalidated `JSON.parse` / `as` cast trusted at a boundary.** Casting parsed JSON or an external value with `as T` asserts a shape the compiler never checked. Validate at trust boundaries with a schema or type guard.
- **Unused imports / exports / dead symbols.** Stale imports and never-consumed exports accumulate. Spot these during review; most linters flag them - confirm the linter actually runs.

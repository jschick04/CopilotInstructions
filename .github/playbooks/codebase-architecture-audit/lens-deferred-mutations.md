# Lens: deferred mutations (§3.8)

## Purpose

Apply AGENTS.md §3.8 (defer state mutations until after success) to in-scope code. Surfaces premature state-recording, unbounded cache growth, stale error breadcrumbs, and idempotency-first reference handoff smells. Sub-file of `codebase-architecture-audit.md`.

## Hard gates

- **Read-only**.
- **Per-lens evidence-gate output** before findings (see *Procedure* step 7).
- **Source-grounded**: every finding cites `file:line` of the mutation AND the success-determining call.

## Inherits

Scope, risk-tolerance, and output destination from the calling index.

## Procedure

1. **Membership / dedup-set early-add** - `grep` for `\.Add\(` / `\[.*\]\s*=` followed by a failable operation that throws or returns false. Anti-pattern: `seen.Add(x); doFailableWork(x);` - should be `doFailableWork(x); seen.Add(x);`.
2. **Registration / init flag early-set** - `grep` for `_registered = true` / `_initialized = true` / similar BEFORE the underlying call. Flag set must happen AFTER the call returns success.
3. **Cache write before success** - `grep` for cache `Add` / `Set` / `[]=` paths that wrap or precede the data-fetching call. Cache writes on the success path only.
4. **High-cardinality cache keys** - flag any cache whose key is built by concatenating per-record fields (timestamps, IDs, paths, user input) and whose `Add` site does not branch on a known-bounded prefix. Includes string-interning caches whose keys aren't actually a small bounded set.
5. **Stale error breadcrumbs on success** - success-path code that does NOT explicitly clear `LastErrorCode` / `LastException` / `_warningShown` / similar prior-failure state. Flag the success site and the unset breadcrumb.
6. **Idempotency-first ref handoff** - methods that are idempotent (early-return if already done) but assign the long-lived reference (interop handle, subscription token) AFTER the early-return guard. Should assign BEFORE the guard; second caller sees `null` and first caller's reference leaks on dispose.
7. **Per-lens evidence-gate output**:

   ```
   Lens deferred-mutations audit: scope=<files scanned, method=grep|view>, M mutation sites examined, F findings.
   - early dedup-add: N - <file:line list OR "none - zero-count justification: every Add/Set found is on the success path per source review">
   - early registration flag: N - <file:line list>
   - cache write before success: N - <file:line list>
   - high-cardinality cache keys: N - <list>
   - stale error breadcrumbs on success: N - <list>
   - idempotency-first ref handoff bugs: N - <list>
   ```

8. **Findings list** - severity, location, issue, proposal, intent-clarity justification.

## Output

Findings list + per-lens evidence-gate audit. Consumed by `codebase-architecture-audit.md` aggregation step.

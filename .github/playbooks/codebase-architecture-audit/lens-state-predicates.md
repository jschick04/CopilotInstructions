# Lens: state predicates (§3.7)

## Purpose

Apply AGENTS.md §3.7 (state predicates and emptiness checks) to in-scope code. Produces a list of state-predicate findings with `file:line` citations. Sub-file of `codebase-architecture-audit.md`; not invoked directly by users.

## Hard gates

- **Read-only**.
- **Per-lens evidence-gate output** before findings (see *Procedure* step 4).
- **Source-grounded**: every finding cites `file:line` of both the predicate AND a missed-field or overlap site.

## Inherits

Scope, risk-tolerance, and output destination from the calling index. No separate intake.

## Procedure

1. **Un-encapsulated boolean composition** — `grep` for multi-clause boolean over fields of a single type, expressed outside that type. Pattern shape: `x.A == 0 && x.B == 0 && !x.C.Any()` where `x: TFoo` is referenced from outside `TFoo`. Suggested grep: `&&.*\.(\w+).*&&.*\.(\w+)` filtered by file; also language-server "find references" on common state-bearing types.
2. **Audit existing state predicates** — for each `IsEmpty` / `IsDefault` / `Equals` / `GetHashCode` over fields, enumerate every member of the type; flag any field NOT included AND not justified-as-excluded.
3. **Match / equality predicate uniqueness** — composite keys over multi-source records (e.g., `(LocalId, SubId)`): could two domain-distinct objects compare equal once they cross their original container? If yes, flag the missing source / owner field.
4. **Per-lens evidence-gate output**:

   ```
   Lens state-predicates audit: scope=<files scanned, method=grep|view|language-server>, P predicate sites examined, F findings.
   - un-encapsulated boolean compositions: N — <file:line list OR "none — zero-count justification: no multi-clause boolean over single-type fields found outside the type in <scope>">
   - incomplete-field predicates: N — <list with predicate location + missed-field location>
   - identity collision risks: N — <list with predicate site + colliding-record sites>
   ```

5. **Findings list** — one entry per finding with severity (blocker / major / minor), location, issue, proposal, intent-clarity justification. Returned to index for aggregation.

## Output

Findings list + per-lens evidence-gate audit. Consumed by `codebase-architecture-audit.md` aggregation step.

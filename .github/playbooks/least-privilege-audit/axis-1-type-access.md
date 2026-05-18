# Axis 1 — Type access modifier

## Goal

Demote `public` → most-restrictive that compiles AND keeps real consumers working. **OR** delete the type entirely when it has zero in-repo consumers and is not exported (per G6 dead-code default-delete clause below).

## Procedure

For each public type, run a worktree-wide consumer search using a word-boundary grep for the type name. Bucket consumers as:

- **SAME-asm consumers** (declaring project) — never block internalization.
- **SAME-asm-FRIEND test consumers** (test project granted `InternalsVisibleTo` / equivalent) — never block internalization (already friended).
- **OTHER-asm prod consumers WITH existing friend-grant** — never block internalization (already friended).
- **OTHER-asm prod consumers WITHOUT friend-grant** — apply the friend-grant-proliferation precedence (below).
- **OTHER-asm test consumers WITHOUT friend grant** — apply the friend-grant-proliferation precedence (below).
- **ZERO in-repo consumers** — apply G6 dead-code default-delete clause (below).

## Friend-grant-proliferation precedence ladder

Per the hard gate in the index — adding a NEW friend-grant exposes ALL current AND future internals to the receiving asm, so it's the LAST resort, not the default:

1. **SPLIT-MEMBER-VISIBILITY** — keep the type at the broader access level needed by the cross-asm consumer, but tighten individual members that have only same-asm callers. Best when the cross-asm consumer needs only a small subset of the type's surface. Language-specific: C# `public` class with mixed `public` / `internal` members; Kotlin `public` class with `internal` members; TypeScript `export class` with only the necessary methods exported / public; Rust `pub` struct with `pub(crate)` methods; Go capitalized type with lowercase methods; C++ `class` with `public` and `private` access labels; Swift `public class` with `internal` members. The cross-asm consumer sees only the subset it needs; same-asm callers retain access to everything else.
2. **CO-LOCATION** — move the type into the consumer's asm so it becomes same-asm. Applies when the type has exactly one cross-asm consumer and no domain reason to live in the declaring asm.
3. **KEEP-PUBLIC** — last resort when the type genuinely belongs in the declaring asm and split-visibility doesn't fit (e.g. record-style data carrier with no internal-only members to tighten).
4. **INTERNAL+ADD-NEW-FRIEND-GRANT** — LAST resort. Only when (a) the cross-asm consumer needs broad surface that defeats split-visibility, AND (b) co-location is wrong domain-wise, AND (c) the public-surface delta from KEEP-PUBLIC would dwarf the friend-grant's coupling cost (e.g. dozens of types vs. one IVT line).

Existing friend-grants on the declaring asm are free to use — re-using an established `<InternalsVisibleTo>` / module export incurs no new proliferation cost.

## Recommendation values

`INTERNAL` / `INTERNAL+REUSE-EXISTING-FRIEND-GRANT` / `SPLIT-MEMBER-VISIBILITY` / `CO-LOCATE-TO-<asm>` / `KEEP-PUBLIC` / `INTERNAL+ADD-NEW-FRIEND-GRANT` (last resort, justify in the matrix) / `DELETE` (per G6, see below) / `KEEP-PUBLIC + FLAG FOR USER APPROVAL` (per G6 conservative default).

## Polyglot examples

- A TypeScript class `export`ed only for same-package tests can become non-exported (rely on subpath exports / vitest's `import` of source).
- A Java class `public` only for same-module callers can be package-private.
- A Rust `pub` item with only same-crate consumers can be `pub(crate)`.
- A Go uppercase identifier with only same-package consumers can be lowercased.

## G6 — Dead-code default-delete (zero in-repo consumers)

When the worktree-wide consumer search returns **zero in-repo consumers** for a type, the default action is **DELETE**, not internalize-as-placeholder. Speculative non-deletion is debt.

### Conservative default — exported / public SDK / package surface

When the type may be consumed by an EXTERNAL consumer the in-repo search cannot see (NuGet / npm package consumers, public SDK surface, framework reflection from outside the repo), the default flips to **KEEP-PUBLIC + FLAG FOR USER APPROVAL** rather than delete. Detect "exported" per language:

- **C#**: declaring project has `<PackageId>` set OR `<IsPackable>true</IsPackable>` OR a `.nuspec` file OR a public-API analyzer baseline file (`PublicAPI.Shipped.txt` / `PublicAPI.Unshipped.txt`) that lists the type or any of its public members. Public members on a public type also count as exported surface — check member-level visibility, not just top-level.
- **TypeScript**: `package.json` has `exports` field (including conditional / nested `exports`) OR `main` field referencing the file OR `bin` entry OR `typings` / `types` / `typesVersions` referencing the file. **Special case**: `types`-only packages (no `exports`, no `main`) export TypeScript declarations but no runtime code — treat the type-declaration surface separately from runtime-reachable code.
- **Java**: `module-info.java` `exports <pkg>` (unqualified) OR `exports <pkg> to <module>` (qualified). For qualified exports, check the named consumer module for actual usage; zero in-repo consumers inside the target module = not protected. For no-`module-info` packages (legacy / automatic modules), any `public` type in a non-internal package is effectively exported.
- **Go**: exported identifiers (capitalized name) OUTSIDE an `internal/` directory boundary. `_test.go` files contribute consumers but not exports.
- **Rust**: `pub` outside `pub(crate)` / `pub(super)` / `pub(in path::...)`. `pub use` re-exports count: a `pub(crate)` item that is `pub use`-re-exported at the crate root is effectively `pub` at the crate boundary.
- **Swift**: `public` or `open` (not `internal` / `fileprivate` / `private`).
- **Python**: listed in `__all__` for an exported module, OR referenced in `pyproject.toml` `[project]` entry-points, OR has no leading `_` AND lives in a package that's listed as a runtime artifact.

When detection is **uncertain** (e.g. the project's pack-targeting is unclear, or a `module-info` is missing in a way that could go either way), default to **KEEP + FLAG FOR USER APPROVAL** — the user names the call.

### Predicate-supporting field carve-out

Fields surfaced by §3.7 state-predicate audits (used by `IsEmpty`, `Equals`, `GetHashCode`, serialization, framework binding, reflection) require **behavior proof** before deletion: a test, usage trace, or runtime read that demonstrates the field is actually read. A field that "looks unused" but is read by EF Core via reflection or by `System.Text.Json` via property reflection is NOT dead code.

### Durable record location for non-deletion

When the audit recommends KEEP (instead of DELETE) for a zero-consumer type based on a near-term feature plan, the rationale lives in **session todos** OR an **issue tracker URL** — NOT in `plan.md` (which is session-scoped and won't survive the session). The matrix entry cites the durable record.

## Output

Per-type matrix entry with Axis 1 recommendation + consumer evidence (file:line citations) + verifying grep command. Feeds the index's per-type matrix aggregation (Procedure step 3).

# Axis 4 — Method / property visibility

## Goal

Tighten members of remaining-public types. Only audit if type stays public after Axis 1.

## Procedure

- Skip interface members (bound by contract).
- Skip overrides of base-class members (must match base visibility).
- Skip framework-required members (Razor `[Parameter]` setters, Razor lifecycle methods, EF Core navigation properties, Fluxor `[ReducerMethod]` / `[EffectMethod]`, JSON converter `Convert*` overrides, Java JPA accessors, etc.).
- For each remaining public member, run a qualified search (`<TypeName>.<MemberName>` or call-site syntax) — be careful of name-collision false positives.
- If only consumed inside the declaring asm: demote to `internal` / package-private / `pub(crate)`.

This axis is best done as representative spot-check (not exhaustive enumeration of every member of every class); flag obvious wins, defer the long tail.

## Output

Per-type matrix entry with Axis 4 recommendation. Feeds the index's matrix aggregation.

# Axis 3 - Constructor visibility

## Goal

Tighten ctors when no external code calls `new TypeName(...)`. Only audit if type stays public after Axis 1.

## Procedure

- Search for `new <TypeName>(` (or language equivalent: Kotlin `<TypeName>(`, Rust `<TypeName>::new(`, Go `<package>.New<TypeName>(`, Python `<TypeName>(`, Swift `<TypeName>(`) across the worktree.
- If only same-asm + friend-asm tests invoke the ctor: tighten ctor visibility to `internal` / package-private / `pub(crate)`.
- If DI / reflection / `Activator.CreateInstance` from the same assembly: internal works (most DI frameworks support internal types when the registering asm has visibility).
- If DI / reflection from a DIFFERENT assembly (e.g. ASP.NET Core controllers in a separate asm): keep ctor public OR add friend grant.

## Output

Per-type matrix entry with Axis 3 recommendation. Feeds the index's matrix aggregation.

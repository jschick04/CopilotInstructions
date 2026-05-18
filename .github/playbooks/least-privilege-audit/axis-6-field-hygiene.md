# Axis 6 — Field hygiene

## Goal

Shrink field surface area; immutability where possible. Only audit if type stays public after Axis 1.

## Procedure

- **`private` non-readonly fields assigned only in ctor** → tighten to immutable:
  - **C#** `readonly`.
  - **Java** `final`.
  - **Kotlin** `val`.
  - **TypeScript** `readonly`.
  - **Rust** (already immutable by default; `mut` is opt-in — verify no `mut` binding leaks).
  - **Go** (no const fields; document via comment).
  - **Swift** `let`.
- **`internal` fields** — check whether `private` would compile.
- **`public` fields** are almost always wrong — convert to property (unless `const` / `static readonly` / Rust `pub const`).

## Output

Per-type matrix entry with Axis 6 recommendation. Feeds the index's matrix aggregation.

# Axis 5 - Property setters / mutability

## Goal

Prevent post-construction mutation by external code unless that mutation is genuinely required. Only audit if type stays public after Axis 1.

## Procedure

For each mutable public property on a remaining-public type, classify writers:

- **Never written outside the declaring type**:
  - **C#**: `private set`.
  - **Kotlin**: `private set` on a `var`.
  - **Java**: drop the setter (and prefer `final`).
  - **TypeScript**: `readonly` modifier.
  - **Rust**: remove `pub` from the field (Rust has no `pub mut` - a `pub` field on a value the caller owns is mutable; restrict by hiding the field and exposing read-only accessors / methods that take `&self`).
  - **Go**: unexport the field; expose a getter method instead.
  - **Swift**: `private(set) var`.
- **Written only via object-initializer / construction-time syntax outside** (e.g. C# `new Foo { Prop = X }`):
  - **C# `init`** (settable at construction, not after).
  - Other languages: factory pattern / builder pattern.
- **Mutated post-construction by external code** - keep mutable.

Records (C#) / data classes (Kotlin) / case classes (Scala) typically have init-only positional params - this axis bites manually-declared properties on classes.

## Output

Per-type matrix entry with Axis 5 recommendation. Feeds the index's matrix aggregation.

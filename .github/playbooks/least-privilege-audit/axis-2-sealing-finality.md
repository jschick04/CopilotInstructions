# Axis 2 — `sealed` / `final` / closed-extension modifier

## Goal

Prevent unintended subclassing; enable compiler / runtime devirtualization where applicable. Only audit if type stays public after Axis 1.

## Procedure

For each non-abstract concrete class, search for derivers across the worktree:

- **C#**: `rg -t cs -P 'class\s+\w+\s*(?:<[^>]+>)?\s*:\s*[^,{]*\b<TypeName>\b'`
- **Java**: `rg -t java -P 'extends\s+<TypeName>\b'`
- **Kotlin**: classes are `final` by default — flag any `open class` without a same-asm subclass for tightening to `final` (remove `open`).
- **TypeScript**: `rg -t ts -P 'extends\s+<TypeName>\b'` — TS has no built-in `final`; use ESLint `no-extend-class` or JSDoc `@final` if the team adopted them.
- **Rust**: structs / enums are not subclassable; sealing a TRAIT is the relevant pattern — flag public traits with downstream impls vs sealed-trait pattern (`mod sealed { pub trait Sealed {} }`).
- **Go**: no inheritance — N/A.
- **C++**: `rg -t cpp -P ':\s*(public|protected|private)\s+<TypeName>\b'` then recommend `final` keyword on the class.
- **Swift**: `rg -t swift -P ':\s+<TypeName>\b'` then recommend `final class`.

If no derivers found: recommend adding the seal / final modifier.

## Framework exceptions (record as NOTE; don't auto-tighten)

- EF Core `DbContext` subclasses — usually NOT sealed (runtime proxy generation needs vtable slots).
- Designed-for-extension exception base classes.
- Spring beans with AOP proxies (Spring uses CGLib subclassing for some proxy modes).
- Hibernate entities (lazy-loading proxies subclass the entity).
- React class components (rare today; functional components don't have this concern).
- Rust traits intended as a public extension point.

When in doubt, FLAG with NOTE rather than auto-recommend; user decides.

## Output

Per-type matrix entry with Axis 2 recommendation + derivers search result. Feeds the index's matrix aggregation.

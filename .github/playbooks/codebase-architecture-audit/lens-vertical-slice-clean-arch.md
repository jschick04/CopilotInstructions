# Lens: vertical slice + clean architecture (§3.12)

## Purpose

Apply AGENTS.md §3.12 (within-assembly folder topology - vertical slice + clean architecture overlay) to in-scope code. Checks whether folders organize by feature / domain (slice) with clean-architecture dependency direction overlaid for cross-cutting types. Sub-file of `codebase-architecture-audit.md`.

## Hard gates

- **Read-only**.
- **Per-lens evidence-gate output** before findings (see *Procedure* step 5).
- **Source-grounded**: every finding cites the folder / namespace path and at least one type living in it.
- **VSA before clean-arch**: vertical slicing takes priority when they conflict (§3.12). Prefer slice ownership; clean-arch layering applies only for cross-cutting types where slice ownership doesn't determine placement.

## Inherits

Scope, risk-tolerance, and output destination from the calling index.

## Procedure

1. **Map folder topology** - enumerate top-level folders / namespaces within in-scope assemblies. For each, classify:
   - **Slice folder**: feature / domain name (`UserAuth/`, `Billing/`, `Workspace/`, `Filtering/`).
   - **Cross-cutting `Common/<Domain>/`**: domain-themed shared types (`Common/Events/`, `Common/Channels/`).
   - **Layer-named (anti-pattern indicator)**: `Application/`, `Domain/`, `Infrastructure/`, `Presentation/` at top-level. Clean-arch terms imply tier-first organization that contradicts §3.12 VSA priority.
   - **Type-bucket (anti-pattern)**: `Models/`, `Services/`, `Helpers/`, `Utils/`, `Common/` (flat).
2. **Slice-ownership audit** - for each shared type in a `Common/<Domain>/`, check whether ≥2 slices consume it. Single-consumer cross-cutting types should live in the consuming slice; surface the type and the single consumer's slice for relocation proposal.
3. **Helper / util / manager anti-pattern** - `grep` for class names ending in `Helper` / `Util` / `Utils` / `Manager`. Propose renaming to what the code does (`FilePathSorter` not `FileHelpers`).
4. **Friend-grant proliferation** - count cross-asm friend grants (C# `<InternalsVisibleTo>`, Java `module-info.java exports ... to`, Kotlin friend-paths, TS `package.json` subpath `exports`, Rust crate friend access). Each grant exposes ALL current AND future internals of the granting asm to the receiving one - high coupling cost. Flag any added cross-asm consumer that would justify a NEW friend grant (vs. reusing an existing one or keeping the type public in `Common/<Domain>/`).
5. **Per-lens evidence-gate output**:

   ```
   Lens vertical-slice-clean-arch audit: scope=<assemblies / folders enumerated>, F findings.
   - layer-named top-level folders: N - <list with paths>
   - flat type-bucket folders: N - <list>
   - Common/<flat>/ (missing domain sub-folder): N - <list>
   - single-consumer cross-cutting types: N - <type path + sole consumer slice>
   - Helper / Util / Manager class-name suffixes: N - <list with file:line>
   - new-friend-grant proliferation risk: N - <list of types whose cross-asm exposure would require a NEW grant>
   - zero-count justification per category that returned 0 (e.g., "flat type-bucket folders: 0 - every shared folder has domain sub-grouping per scan")
   ```

6. **Findings list** - severity (major when slice-violation crosses public API; minor when internal-only), location, issue, proposal. **Intent-clarity justification** typically cites *"slice ownership makes the feature locatable; type-bucket folders force readers to know the type's role before they can navigate"*.

## Output

Findings list + per-lens evidence-gate audit. Consumed by `codebase-architecture-audit.md` aggregation step.

---
name: performance-comparison
description: Use when user wants to compare performance of alternative implementations using a throwaway benchmark harness. Loudly throwaway; never wired into production. Output: working variants + benchmark numbers + decision log. Mandatory handoff to software-install.md when benchmark tooling needs install.
triggers:
  - "compare perf of"
  - "benchmark these approaches"
  - "perf spike on"
  - "performance comparison for"
  - "throw together a benchmark"
  - "measure these alternatives"
---

# Performance comparison

## Purpose

Throwaway prototype with a benchmark harness for performance comparison between alternative implementations. Same throwaway-hardening discipline as `design-exploration.md` (companion playbook). Output: working variants + benchmark numbers (metric chosen at intake) + a short decision log capturing trade-offs and the chosen direction. Mandatory handoff to `software-install.md` when benchmark tooling (`BenchmarkDotNet`, `hyperfine`, `locust`, `wrk`, `criterion`, etc.) needs to be installed.

## Hard gates

Inherits all throwaway hardening from `design-exploration.md` (folder discipline / canonical header on comment-capable files / sibling `README.md` for non-commentable / build isolation / zero production-to-prototype imports / cleanup-or-expiry gate). The §3.1 narrow exception for the canonical `THROWAWAY:` header applies here identically - header is load-bearing, not narrative.

Additional hard gates for performance work:

- **Evidence-gate output** with metric + delta + hardening fields (see *Procedure* step 5).
- **Mandatory `software-install.md` handoff**: when the chosen benchmark tooling is not installed in the user's environment, `software-install.md` runs with all its hard gates (platform package manager first, signature verification, etc.) BEFORE the benchmark harness is authored. Record the install handoff outcome in the evidence-gate output.
- **Environment capture**: every benchmark run records machine spec, OS, runtime version, warmup count, sample size in the decision log so numbers are reproducible.
- **Catalog rule cross-references**: this playbook's invariants are continuously enforced by THREE catalog rules:
  - `prototype-imported-by-production` (HIGH, tree-scoped rg) - inherited from design-exploration; flags production-code imports of `prototypes/`.
  - `prototype-file-missing-throwaway-marker` (MEDIUM, review-pass-only) - inherited from design-exploration; flags new `prototypes/` files without the `THROWAWAY:` header.
  - `perf-claim-without-environment-capture` (MEDIUM, review-pass-only) - specific to performance work. Fires when PR description / commit message / code comment makes a QUANTITATIVE perf claim (e.g., `30% faster`, `5x throughput`, `15ms latency`, `300μs faster`, `N% lower CPU`) WITHOUT environment-capture fields (machine / OS / runtime / warmup / sample size) or a link to a documented benchmark artifact. Casual qualitative claims (`"faster"`, `"more efficient"`) with no number do NOT fire.
  
  See `pr-quality-gate/pattern-catalog.md` for full audit methods.

## Phase enforcement

OFFERED class. Detected at `pre-implementation.md` G6 step when the plan has a quantitative perf goal (numeric throughput / latency / memory target; user-stated). Enforced by ONE pre-impl catalog rule plus the existing prototype + perf invariants:

- `pre-impl-skipped-performance-comparison-when-quantitative-goal` (MEDIUM, pre-impl) - fires when G6 detected the trigger but POST-CODE-CHANGE LEDGER `gates.pre-impl-playbook-decisions.performance-comparison` is missing OR `not-applicable` (silent-downgrade bypass). Valid values when detected: `invoked` / `offered-and-declined: "<user-quoted justification>"` / `required-but-skipped: "<reason>"`.

Prototype + perf invariants (continuously enforced, NOT pre-impl-only) - `prototype-imported-by-production` (HIGH), `prototype-file-missing-throwaway-marker` (MEDIUM), `perf-claim-without-environment-capture` (MEDIUM). See *Hard gates* above.

## Intake questions

Bundle in one `ask_user` prompt:

1. **What's being compared**: one-sentence framing (e.g., "lock-based vs lock-free queue throughput", "JSON.NET vs System.Text.Json deserialization at N=10k", "linear vs binary search on N=10k sorted input").
2. **Metric**: latency (p50 / p99), throughput, memory allocations, CPU, wall-clock duration, or composite. Required - drives benchmark harness design.
3. **Variant count**: how many alternatives? Default 2-3.
4. **Tooling**: which benchmark framework. Defaults per language: .NET → `BenchmarkDotNet`; Go → `testing.B`; Rust → `criterion`; Python → `pytest-benchmark` / `pyperf`; JS/TS → `vitest bench` / `benchmark.js`; CLI / cross-language → `hyperfine`. Confirm the framework is installed or trigger `software-install.md`.
5. **Destination folder**: default `prototypes/<name>/` at repo root.
6. **Retention**: same as `design-exploration.md` (delete / commit-as-artifact / expiry-event defer).
7. **Sample / iteration parameters**: warmup count, sample size, input size(s) - defaults per tooling but ask if non-default.

## Procedure

1. **Tooling install check** - verify chosen tooling is installed (`<tool> --version` or equivalent). If not, run `software-install.md` with its hard gates; record the install outcome (phase-state record citation) in the evidence-gate output.
2. **Scaffold the prototype folder** - `prototypes/<name>/` with one subfolder per variant + a shared harness folder (`benchmarks/` or framework-specific).
3. **Author the harness + variants** - minimal runnable code. Apply throwaway markers (header on comment-capable files; sibling `README.md` for non-commentable). Each variant exposes the same API / contract; the harness measures the chosen metric uniformly across variants.
4. **Run the benchmark** - capture before / after metric numbers for each variant. Record warmup count, sample size, environment (machine, OS, runtime version) in the decision log so numbers are reproducible.
5. **Evidence-gate output** (chat-visible before the decision log):

   ```
   Perf comparison audit: N variants, R benchmark runs, metric=<latency-p50 | latency-p99 | throughput | allocations | cpu | wall-clock | composite>, tooling install handoff=<not-needed | software-install.md run; citation: <phase-state record>>.
   - <variant>: <metric value> (e.g., "1.42 ms ± 0.03 (n=1000, warmup=100)")
   - <variant>: <metric value>
   - delta: <pct or absolute delta vs baseline variant>
   - environment: <machine spec, OS, runtime version> (citation: captured by harness)
   - throwaway markers compliant: yes (folder + per-file headers OR sibling README for non-commentable), production imports of prototype: 0 (grep verified, scope=<production glob>), build isolation: confirmed (exclude method=<X>)
   - cleanup/expiry decision: <delete | commit-as-artifact (rationale) | defer-with-expiry: <event>>
   ```

6. **Decision log** (chat-rendered; may be saved to `prototypes/<name>/DECISION.md`) - metric outcomes, qualitative trade-offs per variant (readability, complexity, dependency weight), chosen direction, what's NOT being pursued and why.
7. **Cleanup gate** - apply retention decision (delete / commit-as-artifact / expiry-event defer). When commit-as-artifact, verify build-isolation grep still shows 0 production imports BEFORE the commit.

## Output

Working variants + benchmark results in `prototypes/<name>/` + chat-rendered decision log + perf comparison evidence-gate output. Retention per intake.

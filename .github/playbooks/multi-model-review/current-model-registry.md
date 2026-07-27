# Capability tier → current model registry (multi-model-review consumers)

This file is the canonical mapping from the abstract slate-slot capability tiers (used by `multi-model-review.md` consumers, including `pre-pr-creation-review.md` and `post-code-change.md` §3) to the currently-available model names. Decoupling the slot definition from the model name prevents playbooks from breaking when models are deprecated or new tiers appear.

## Update contract

- **Owner**: any contributor making a model-related change in this instruction repo (no single designated owner; the file lives next to the playbooks that consume it).
- **Update trigger**: a model named in the table below is deprecated, removed, or renamed in the runtime catalog; a new model is added that supersedes one currently in the table; or an existing model materially changes capability tier.
- **Update SLA**: same PR as the playbook / instruction change that depends on the new mapping. Do NOT land a playbook change that references a model name not in this table; conversely, do not delete a name from this table that a playbook still references without updating both.
- **Validation**: after editing this file, run `git --no-pager grep -in -E '<pattern>' -- . ':!.github/pr-quality-gate/pattern-catalog*' ':!scripts/tests'` (or `rg -in --hidden` with equivalent `--glob '!'` exclusions) for (a) each removed model name, (b) each removed or renamed tier id, and (c) `cross[- ]version`. Expect 0 hits. A bare `rg <token> .` silently skips `.github/` because it is a hidden directory, so it must not be used here. `scripts/tests` is excluded because those fixtures assert the ledger grammar, which treats `model:(\S+)` opaquely with no allowlist (`scripts/lib/panel-ledger-helpers.psm1`), not catalog membership.

## Capability tiers

| Tier id | Description |
| --- | --- |
| `heavy-claude-xhigh` | Top-of-line Claude model with extra-high / max reasoning effort. Used for deep architectural reasoning, design critique, and the slot 1 anchor reviewer. |
| `heavy-claude-standard` | Top-of-line Claude model at standard reasoning. Used for the rubber-duck slot when the orchestrator is Claude-family. |
| `heavy-claude-cross-profile` | A Claude model differing from `heavy-claude-standard` in reasoning profile or version line, for additional within-family diversity. Used when a panel needs Claude-family triangulation beyond the standard slot (mirrors `heavy-gpt-cross-profile`). |
| `heavy-gpt-premium` | Top-of-line GPT model with premium reasoning. Used for slot 2 (different family from slot 1). |
| `heavy-gpt-codex` | Top-of-line code-specialized GPT model. Used for slot 3 (within-family triangulation against premium). |
| `heavy-gpt-cross-profile` | A GPT model differing from `heavy-gpt-premium` in reasoning profile or version line, for additional within-family diversity. Used for slot 4. |
| `light-claude` | Lighter / faster Claude model (Haiku-tier or similar). Used for per-commit panels where context budget matters. |
| `light-gpt` | Lighter / faster GPT model. Used for per-commit panels. |
| `light-claude-balanced` | Mid-size Claude (Sonnet-tier) between heavy and light. Used for per-commit panels needing more depth than light-claude. |
| `heavy-gemini-premium` | Top-of-line Gemini model with premium reasoning. Provides third-vendor (non-Claude, non-GPT) cross-family diversity; the required Gemini-family slot in panel slate floors. |
| `light-gemini` | Lighter / faster Gemini model (flash-tier). Used for per-commit panels where context budget matters. |
| `light-mai-code` | Code-specialized lightweight model (MAI-Code family). Optional fast code-focused perspective for per-commit / cost-sensitive panels. |

## Current mapping

| Tier id | Current model | Notes |
| --- | --- | --- |
| `heavy-claude-xhigh` | `claude-opus-5` | Top-of-line Opus at xhigh/max reasoning effort; supersedes `claude-opus-4.8` for this tier (4.8 is retained as `heavy-claude-cross-profile`). |
| `heavy-claude-standard` | `claude-opus-5` | - |
| `heavy-claude-cross-profile` | `claude-opus-4.8` | Prior Opus version line; decorrelates failure modes from `claude-opus-5`. |
| `heavy-gpt-premium` | `gpt-5.6-sol` | Deepest-reasoning member of the 5.6 line. |
| `heavy-gpt-codex` | `gpt-5.3-codex` | Distinct 5.3 lineage; the within-GPT independence anchor. |
| `heavy-gpt-cross-profile` | `gpt-5.6-terra` | Balanced 5.6 tuning; differs from `gpt-5.6-sol` in reasoning depth, not version line. |
| `light-claude` | `claude-haiku-4.5` | - |
| `light-gpt` | `gpt-5.6-luna` | Fast / low-cost member of the 5.6 line. |
| `light-claude-balanced` | `claude-sonnet-5` | - |
| `heavy-gemini-premium` | `gemini-3.1-pro-preview` | Third-vendor family; required slate-floor slot. |
| `light-gemini` | `gemini-3.6-flash` | - |
| `light-mai-code` | `mai-code-1-flash-picker` | Code-specialized light tier. |

## Within-family diversity note

`heavy-gpt-premium` and `heavy-gpt-cross-profile` are both drawn from the `gpt-5.6` line, so they share a training lineage and can fail in correlated ways. Within-GPT independence rests on `heavy-gpt-codex`'s distinct 5.3 lineage plus the tuning spread between the two 5.6 profiles; cross-family independence (Claude + Gemini) carries the remainder of the slate floor. `heavy-claude-xhigh` and `heavy-claude-standard` resolve to the same model in different roles, as they did before this mapping. A six-slot panel is therefore not six model-independent observations.

## Runtime fallback rule

When this file is missing entirely (early-bootstrap state, fresh consuming repo without this file pulled in yet, or temporary deletion): the orchestrator falls back to its runtime model catalog and selects the highest-capability model from the requested family that is currently available. Record the fallback substitution in the consuming playbook's evidence-gate output under `slate_substitutions` with `reason: registry-missing`.

When this file is present but a specific tier id has no mapping (a tier referenced by a playbook that wasn't yet entered into the table): same fallback rule, with `reason: tier-not-mapped`.

## Substitution rule when a specific model is unavailable

When a model named in the table is unavailable (API down, deprecated, removed from runtime catalog) but the tier is still mapped: substitute the highest-capability successor from the same family + comparable capability tier. Record the substitution with `reason: model-unavailable` and the substitute's name.

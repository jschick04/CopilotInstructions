# Capability tier → current model registry (multi-model-review consumers)

This file is the canonical mapping from the abstract slate-slot capability tiers (used by `multi-model-review.md` consumers, including `pre-pr-creation-review.md` and `post-code-change.md` §3) to the currently-available model names. Decoupling the slot definition from the model name prevents playbooks from breaking when models are deprecated or new tiers appear.

## Update contract

- **Owner**: any contributor making a model-related change in this instruction repo (no single designated owner; the file lives next to the playbooks that consume it).
- **Update trigger**: a model named in the table below is deprecated, removed, or renamed in the runtime catalog; a new model is added that supersedes one currently in the table; an existing model materially changes capability tier; a mapped model's supported `context_tier` changes; or a mapped model's supported effort set changes such that the configured tier `effort` is no longer supported. `effort` is a tier-POLICY value changed only by a deliberate tier decision - NEVER synced to the model's ceiling because the catalog moved.
- **Update SLA**: same PR as the playbook / instruction change that depends on the new mapping. Do NOT land a playbook change that references a model name not in this table; conversely, do not delete a name from this table that a playbook still references without updating both.
- **Validation**: after editing this file, run `git --no-pager grep -in -E '<pattern>' -- . ':!.github/pr-quality-gate/pattern-catalog*' ':!scripts/tests'` (or `rg -in --hidden` with equivalent `--glob '!'` exclusions) for (a) each removed model name, (b) each removed or renamed tier id, and (c) `cross[- ]version`. Expect 0 hits. A bare `rg <token> .` silently skips `.github/` because it is a hidden directory, so it must not be used here. `scripts/tests` is excluded because those fixtures assert the ledger grammar, which treats `model:(\S+)` opaquely with no allowlist (`scripts/lib/panel-ledger-helpers.psm1`), not catalog membership. Then run `pwsh -File scripts/check-model-registry.ps1`, which enforces this file's table shape, the `effort` / `context_tier` / `consumers` value sets, and tier-id parity - but CANNOT verify that a capability value is true for a given model, since no runtime oracle exists. Re-verify `effort` and `context_tier` by hand against the runtime catalog.

## Capability tiers

| Tier id | Description |
| --- | --- |
| `heavy-claude-xhigh` | Top-of-line Claude model with extra-high / max reasoning effort. Used for deep architectural reasoning, design critique, and the slot 1 anchor reviewer. |
| `heavy-claude-standard` | Top-of-line Claude model at standard reasoning. Used for the rubber-duck slot when the orchestrator is Claude-family. |
| `heavy-claude-cross-profile` | A Claude model differing from `heavy-claude-standard` in reasoning profile or version line, for additional within-family diversity. Used when a panel needs Claude-family triangulation beyond the standard slot (mirrors `heavy-gpt-cross-profile`). |
| `heavy-gpt-premium` | Top-of-line GPT model with premium reasoning. Used for slot 2 (different family from slot 1). |
| `heavy-gpt-codex` | Top-of-line code-specialized GPT model. Used for slot 3 (within-family triangulation against premium). |
| `heavy-gpt-cross-profile` | A GPT model differing from `heavy-gpt-premium` in reasoning profile or version line, for additional within-family diversity. Used for slot 4. |
| `light-claude` | Lighter / faster Claude model (Haiku-tier or similar). Available for cost- and latency-sensitive per-commit panels; no default slate selects it today. |
| `light-gpt` | Lighter / faster GPT model. Used for per-commit panels. |
| `light-claude-balanced` | Mid-size Claude (Sonnet-tier) between heavy and light. Used for per-commit panels needing more depth than light-claude. |
| `heavy-gemini-premium` | Top-of-line Gemini model with premium reasoning. Provides third-vendor (non-Claude, non-GPT) cross-family diversity; the required Gemini-family slot in panel slate floors. |
| `light-gemini` | Lighter / faster Gemini model (flash-tier). Used for per-commit panels where turnaround and cost matter. |
| `light-mai-code` | Code-specialized lightweight model (MAI-Code family). Optional fast code-focused perspective for per-commit / cost-sensitive panels. |

## Current mapping

`effort` is the reasoning effort this tier RUNS at - a tier-policy value, NOT necessarily the model's ceiling. `context_tier` is a capability fact using the exact runtime values `default` / `long_context`. `not-supported` is a REPO SENTINEL, not a runtime enum value: the model exposes no effort control, so no effort argument is sent. `consumers` records which selector surfaces reference the tier. Shape and values are enforced by `scripts/check-model-registry.ps1`.

| Tier id | Current model | effort | context_tier | consumers | Notes |
| --- | --- | --- | --- | --- | --- |
| `heavy-claude-xhigh` | `claude-opus-5` | max | long_context | default slate, sub-agent default | Top-of-line Opus; supersedes `claude-opus-4.8` for this tier (4.8 is retained as `heavy-claude-cross-profile`). |
| `heavy-claude-standard` | `claude-opus-5` | high | long_context | default slate, sub-agent default | `high` is DELIBERATELY below `claude-opus-5`'s `max` ceiling; it is what keeps this tier distinct from `heavy-claude-xhigh`. Never sync it to the ceiling. |
| `heavy-claude-cross-profile` | `claude-opus-4.8` | max | long_context | no default slate consumer | Prior Opus version line; decorrelates failure modes from `claude-opus-5`. |
| `heavy-gpt-premium` | `gpt-5.6-sol` | max | long_context | default slate | Deepest-reasoning member of the 5.6 line. |
| `heavy-gpt-codex` | `gpt-5.3-codex` | xhigh | default | default slate | Distinct 5.3 lineage; the within-GPT independence anchor. The only heavy tier at `default` context. No overflow has been observed and no substitution reason exists for one: an overflow surfaces as a reviewer drop per `panel-policy.md` drop handling (1 -> same family+role+tier replacement, which re-selects this same model and re-drops; 2 -> `ask_user`; >=3 -> abort), or as a pre-launch Checkpoint #1 abort. |
| `heavy-gpt-cross-profile` | `gpt-5.6-terra` | max | long_context | default slate | Balanced 5.6 tuning; differs from `gpt-5.6-sol` in reasoning depth, not version line. |
| `light-claude` | `claude-haiku-4.5` | not-supported | default | no default slate consumer | Exposes no effort control. |
| `light-gpt` | `gpt-5.6-luna` | max | long_context | lite slate | Fast / low-cost member of the 5.6 line. |
| `light-claude-balanced` | `claude-sonnet-5` | max | long_context | lite slate, sub-agent default | - |
| `heavy-gemini-premium` | `gemini-3.1-pro-preview` | high | long_context | default slate | Third-vendor family; required slate-floor slot. `high` is this model's ceiling. |
| `light-gemini` | `gemini-3.6-flash` | high | long_context | lite slate | `high` is this model's ceiling. |
| `light-mai-code` | `mai-code-1-flash-picker` | high | default | no default slate consumer | Code-specialized light tier. |

## Within-family diversity note

`heavy-gpt-premium` and `heavy-gpt-cross-profile` are both drawn from the `gpt-5.6` line, so they share a training lineage and can fail in correlated ways. Within-GPT independence rests on `heavy-gpt-codex`'s distinct 5.3 lineage plus the tuning spread between the two 5.6 profiles; cross-family independence (Claude + Gemini) carries the remainder of the slate floor. `heavy-claude-xhigh` and `heavy-claude-standard` resolve to the same model at different reasoning efforts (`max` vs `high`) in different roles - a real but weaker differentiator than distinct models. A six-slot panel is therefore not six model-independent observations.

## Runtime fallback rule

When this file is missing entirely (early-bootstrap state, fresh consuming repo without this file pulled in yet, or temporary deletion): the orchestrator falls back to its runtime model catalog and selects the highest-capability model from the requested family that is currently available. Record the fallback substitution in the consuming playbook's evidence-gate output under `slate_substitutions` with `reason: registry-missing`.

When this file is present but a specific tier id has no mapping (a tier referenced by a playbook that wasn't yet entered into the table): same fallback rule, with `reason: tier-not-mapped`.

## Substitution rule when a specific model is unavailable

When a model named in the table is unavailable (API down, deprecated, removed from runtime catalog) but the tier is still mapped: substitute the highest-capability successor from the same family + comparable capability tier. Record the substitution with `reason: model-unavailable` and the substitute's name.

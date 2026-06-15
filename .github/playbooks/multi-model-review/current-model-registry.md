# Capability tier → current model registry (multi-model-review consumers)

This file is the canonical mapping from the abstract slate-slot capability tiers (used by `multi-model-review.md` consumers, including `pre-pr-creation-review.md` and `post-code-change.md` §3) to the currently-available model names. Decoupling the slot definition from the model name prevents playbooks from breaking when models are deprecated or new tiers appear.

## Update contract

- **Owner**: any contributor making a model-related change in this instruction repo (no single designated owner; the file lives next to the playbooks that consume it).
- **Update trigger**: a model named in the table below is deprecated, removed, or renamed in the runtime catalog; a new model is added that supersedes one currently in the table; or an existing model materially changes capability tier.
- **Update SLA**: same PR as the playbook / instruction change that depends on the new mapping. Do NOT land a playbook change that references a model name not in this table; conversely, do not delete a name from this table that a playbook still references without updating both.
- **Validation**: after editing this file, `grep` the playbooks directory for the old model name to confirm no stale references remain.

## Capability tiers

| Tier id | Description |
| --- | --- |
| `heavy-claude-xhigh` | Top-of-line Claude model with extra-high / max reasoning effort. Used for deep architectural reasoning, design critique, and the slot 1 anchor reviewer. |
| `heavy-claude-standard` | Top-of-line Claude model at standard reasoning. Used for the rubber-duck slot when the orchestrator is Claude-family. |
| `heavy-claude-cross-version` | A Claude model from a different version line than `heavy-claude-standard` for additional within-family diversity. Used when a panel needs Claude-family triangulation beyond the standard slot (mirrors `heavy-gpt-cross-version`). |
| `heavy-gpt-premium` | Top-of-line GPT model with premium reasoning. Used for slot 2 (different family from slot 1). |
| `heavy-gpt-codex` | Top-of-line code-specialized GPT model. Used for slot 3 (within-family triangulation against premium). |
| `heavy-gpt-cross-version` | A GPT model from a different version line than `heavy-gpt-premium` for additional within-family diversity. Used for slot 4. |
| `light-claude` | Lighter / faster Claude model (Haiku-tier or similar). Used for per-commit panels where context budget matters. |
| `light-gpt` | Lighter / faster GPT model (mini-tier or similar). Used for per-commit panels. |
| `light-claude-balanced` | Mid-size Claude (Sonnet-tier) between heavy and light. Used for per-commit panels needing more depth than light-claude. |
| `heavy-gemini-premium` | Top-of-line Gemini model with premium reasoning. Provides third-vendor (non-Claude, non-GPT) cross-family diversity; the required Gemini-family slot in panel slate floors. |
| `light-gemini` | Lighter / faster Gemini model (flash-tier). Used for per-commit panels where context budget matters. |
| `light-mai-code` | Code-specialized lightweight model (MAI-Code family). Optional fast code-focused perspective for per-commit / cost-sensitive panels. |

## Current mapping (illustrative; update per the contract above)

| Tier id | Current model | Notes |
| --- | --- | --- |
| `heavy-claude-xhigh` | `claude-opus-4.8` | Top-of-line Opus at xhigh/max reasoning effort (supersedes the 4.7-xhigh line). |
| `heavy-claude-standard` | `claude-opus-4.8` | - |
| `heavy-claude-cross-version` | `claude-opus-4.7` | Different version line from `heavy-claude-standard`. |
| `heavy-gpt-premium` | `gpt-5.5` | - |
| `heavy-gpt-codex` | `gpt-5.3-codex` | - |
| `heavy-gpt-cross-version` | `gpt-5.4` | Different reasoning profile from gpt-5.5. |
| `light-claude` | `claude-haiku-4.5` | - |
| `light-gpt` | `gpt-5.4-mini` | Updated cycle 5 to newer mini-tier version line. |
| `light-claude-balanced` | `claude-sonnet-4.6` | - |
| `heavy-gemini-premium` | `gemini-3.1-pro-preview` | Third-vendor family; required slate-floor slot. |
| `light-gemini` | `gemini-3.5-flash` | - |
| `light-mai-code` | `mai-code-1-flash-internal` | Internal MAI-Code family; code-specialized light tier. |

## Runtime fallback rule

When this file is missing entirely (early-bootstrap state, fresh consuming repo without this file pulled in yet, or temporary deletion): the orchestrator falls back to its runtime model catalog and selects the highest-capability model from the requested family that is currently available. Record the fallback substitution in the consuming playbook's evidence-gate output under `slate-substitutions` with `reason: registry-missing`.

When this file is present but a specific tier id has no mapping (a tier referenced by a playbook that wasn't yet entered into the table): same fallback rule, with `reason: tier-not-mapped`.

## Substitution rule when a specific model is unavailable

When a model named in the table is unavailable (API down, deprecated, removed from runtime catalog) but the tier is still mapped: substitute the highest-capability successor from the same family + comparable capability tier. Record the substitution with `reason: model-unavailable` and the substitute's name.

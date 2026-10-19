# Capability tier → current model registry (multi-model-review consumers)

This file is the canonical mapping from the abstract slate-slot capability tiers (used by `multi-model-review.md` consumers, including `pre-pr-creation-review.md` and `post-code-change.md` §3) to the currently-available model names. Decoupling the slot definition from the model name prevents playbooks from breaking when models are deprecated or new tiers appear.

## Update contract

- **Owner**: any contributor making a model-related change in this instruction repo (no single designated owner; the file lives next to the playbooks that consume it).
- **Update trigger**: a model named in the table below is deprecated, removed, or renamed in the runtime catalog; a new model is added that supersedes one currently in the table; an existing model materially changes capability tier; a mapped model's supported `context_tier` changes; or a mapped model's supported effort set changes such that the configured tier `effort` is no longer supported. `effort` is a tier-POLICY value changed only by a deliberate tier decision - NEVER synced to the model's ceiling because the catalog moved.
- **Update SLA**: same PR as the playbook / instruction change that depends on the new mapping. Do NOT land a playbook change that references a model name not in this table; conversely, do not delete a name from this table that a playbook still references without updating both.
- **Validation**: after editing this file, run `git --no-pager grep -in -E '<pattern>' -- . ':!.github/pr-quality-gate/pattern-catalog*' ':!scripts/tests'` (or `rg -in --hidden` with equivalent `--glob '!'` exclusions) for (a) each removed model name, (b) each removed or renamed tier id, and (c) `cross[- ]version`. Expect 0 hits. A bare `rg <token> .` silently skips `.github/` because it is a hidden directory, so it must not be used here. `scripts/tests` is excluded because those fixtures assert the ledger grammar, which treats `model:(\S+)` opaquely with no allowlist (`scripts/lib/panel-ledger-helpers.psm1`), not catalog membership. Then run `pwsh -File scripts/check-model-registry.ps1`, which enforces this file's table shape, the `effort` / `context_tier` / `consumers` value sets, tier-id parity, and that no two tiers share one (model, effort, context_tier) triple - model names are compared trimmed, because `` ` x ` `` and `` `x` `` render as the same code span and so name the same slot - but CANNOT verify that a capability value is true for a given model, since no runtime oracle exists. Re-verify `effort` and `context_tier` by hand against the runtime catalog. The checker locates each table by exact sentinel lines rather than by parsing markdown: `<!-- registry:tiers:begin -->` / `<!-- registry:tiers:end -->` around the capability-tiers table, and `<!-- registry:mapping:begin -->` / `<!-- registry:mapping:end -->` around the mapping table. Each sentinel must appear exactly once, the end must follow the begin, and every line between a pair must be a table row - blank lines included, because a blank line ends a table in GFM. Each table's header row must also appear exactly once in the whole file, immediately after its begin sentinel: this file therefore holds exactly one capability-tiers table and one mapping table, since a second copy anywhere would render as authoritative to a reader while going unvalidated. Nothing else about the file's markdown is constrained - headings, prose, examples, fenced blocks, `---` and list items are all free-form outside the sentinel pairs. Three exceptions, all of which exist to keep the two sentinel-delimited tables the only tables in the file. First, no table delimiter row may appear outside the spans, with any leading blockquote markers stripped first. A delimiter row is GFM's own grammar: optional outer pipes, and every cell a run of dashes with optional leading and trailing alignment colons. Every GFM table needs one, so this closes pipe-less, indented, list-nested and blockquoted copies alike - including the one-column form, which needs no pipe at all, since `:---` on its own renders a table. A bare `---` stays legal because it is a setext underline or thematic break and renders no table; a vertical tab or form feed on that line breaks the setext reading while still counting as delimiter whitespace, so a VT- or FF-padded dash run does render a table and is rejected, where `---` and a tab-padded `---` are not. Three of the shapes that come closest to the grammar without meeting it - `::---`, `-:-` and `--- || ---` - are left alone, because they fail the cell production rather than merely looking delimiter-ish. The rule is deliberately over-inclusive in the other direction: it has no notion of containers, so a delimiter row that a leading list marker or four columns of indentation would have suppressed at top level is still rejected. That over-inclusion is load-bearing and must not be "corrected" - the very same indents render a real table when they sit inside a list item, so an indentation limit would reopen the hole it appears to close. Rejecting a line that renders nothing costs a contributor one code span; accepting one that renders is a false model name published as authoritative. Second, no line anywhere in the file - inside the spans included - may contain raw HTML table markup, the `table`, `thead`, `tbody`, `tr`, `td` and `th` elements, because an HTML table renders as authoritative without a delimiter row, and one written into a Notes or Description cell renders nested inside the validated table while the row around it validates clean. Third, neither rule has any notion of containers, so a matching line counts even inside a fenced block or an HTML comment. The rules match differently, and that decides how to quote them: the sentinel and header rules compare exact line content and the delimiter rule tests the whole line against a character class before parsing it as a delimiter row, so for all three an inline code span is enough to mention them safely; the HTML rule matches the tag anywhere on the line, so an inline code span does not protect it and the element names must be written without a leading angle bracket, as above. One bound the checker deliberately does not enforce: if the sentinel pair itself were moved inside a fence or comment, the file would render no table at all rather than a wrong one, which is loud rather than silent and publishes no false model name.

## Capability tiers

<!-- registry:tiers:begin -->
| Tier id | Description |
| --- | --- |
| `heavy-claude-standard` | Heavy Claude reviewer for the default full slate and full-risk rubber-duck role. |
| `heavy-gpt-premium` | Heavy GPT reviewer for the default full slate. |
| `heavy-gemini-premium` | Heavy Gemini reviewer for the default full slate. |
| `heavy-grok-premium` | Heavy Grok reviewer for the default full slate. |
| `heavy-gpt-codex` | Heavy code-specialized GPT reviewer, optional fifth full-slate reviewer and fallback for unavailable Grok. |
| `light-claude-balanced` | Light Claude reviewer used in triage mode. |
| `light-gpt` | Light GPT reviewer used in triage mode. |
| `light-gemini` | Light Gemini fallback reviewer used in triage mode. |
<!-- registry:tiers:end -->

## Current mapping


`effort` is the reasoning effort this tier RUNS at - a tier-policy value, NOT necessarily the model's ceiling. `context_tier` is a capability fact using the exact runtime values `default` / `long_context`. `not-supported` is a REPO SENTINEL, not a runtime enum value: the model exposes no effort control, so no effort argument is sent. `consumers` records which selector surfaces reference the tier. Shape and values are enforced by `scripts/check-model-registry.ps1`.
<!-- registry:mapping:begin -->
| Tier id | Current model | effort | context_tier | consumers | Notes |
| --- | --- | --- | --- | --- | --- |
| `heavy-claude-standard` | `claude-opus-5.5` | xhigh | long_context | default slate | Full-slate rubber-duck reviewer. |
| `heavy-gpt-premium` | `gpt-6.1-sol` | xhigh | long_context | default slate | Full-slate GPT code reviewer. |
| `heavy-gemini-premium` | `gemini-4-argon` | high | long_context | default slate | Full-slate Gemini code reviewer. |
| `heavy-grok-premium` | `grok-4.7` | xhigh | long_context | default slate | Full-slate Grok code reviewer. |
| `heavy-gpt-codex` | `gpt-5.3-codex` | xhigh | default | default slate | Optional fifth full-slate reviewer; fallback for unavailable Grok. |
| `light-claude-balanced` | `claude-sonnet-5.5` | high | long_context | triage | Default triage Claude reviewer. |
| `light-gpt` | `gpt-6-luna` | high | long_context | triage | Default triage GPT reviewer. |
| `light-gemini` | `gemini-3.8-flash` | high | long_context | triage | Triage fallback when a default family is unavailable. |
<!-- registry:mapping:end -->

## Cross-family diversity note

The full slate uses four model families: Claude, GPT, Gemini and Grok. The optional fifth slot adds a distinct GPT model. If Grok is unavailable, `heavy-gpt-codex` is the only sanctioned substitute. The triage slate uses two light reviewers from distinct families; `light-gemini` is the fallback when a default family is unavailable.

## Runtime fallback rule

When this file is missing entirely (early-bootstrap state, fresh consuming repo without this file pulled in yet, or temporary deletion): the orchestrator falls back to its runtime model catalog and selects the highest-capability model from the requested family that is currently available. Record the fallback substitution in the consuming playbook's evidence-gate output under `slate_substitutions` with `reason: registry-missing`.

When this file is present but a specific tier id has no mapping (a tier referenced by a playbook that wasn't yet entered into the table): same fallback rule, with `reason: tier-not-mapped`.

## Substitution rule when a specific model is unavailable

Substitutions follow the checker-enforced rule in `panel-policy.md` §Checker-enforced ledger rows: one `slate-substitution` row per changed slot with `reason:` `model-retired`, `model-superseded`, `tier-added`, or `family-unavailable` (Grok -> `heavy-gpt-codex` only), one acknowledged `registry-rotation` row, same-vendor rotation, and every heavy model on `data/heavy-allowlist.txt`. There is no free-form `model-unavailable` successor substitution.

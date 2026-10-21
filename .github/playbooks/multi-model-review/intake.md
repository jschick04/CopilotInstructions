# Multi-model review - Intake

Intake questions for `multi-model-review.md`. Bundle independent questions in one `ask_user` prompt; ask sequentially only when a later question depends on an earlier answer.

## Required intake

1. **Review-target type** - what's being reviewed:
   - `plan` - a planning artifact (e.g., `plan.md`, design spec draft, ADO work-item draft).
   - `design` - design doc, current-state survey, architecture proposal.
   - `spec` - interface spec, schema spec, contract spec.
   - `diff` - a code diff (staged, branch-vs-base, or a specific commit range). Default when called by `post-code-change.md` as the panel hard gate.
   - `bug-investigation` - cross-file bug hunt on user-pointed unchanged code via lane-specialized reviewers. Called by `cross-file-bug-investigation.md`. When this target-type is selected, intake passes additional fields: `lanes` (the selected lane slugs from `cross-file-bug-investigation/lanes-catalog.md`), `slot_to_lane_mapping` (round-robin assignment per `procedure.md`), and `scope_file_list`. Lane-specific critique-focus paragraphs are inserted into each reviewer's sub-agent prompt via `procedure.md`'s `bug-investigation` template branch.
   - `custom` - user-supplied target; the user provides the focus / scope.

2. **Review-target location** - a file path, branch range, or chat-attached content. Reviewers receive this as a path or reference; each reviewer reads the source independently via `view` / `grep` rather than receiving inline content (preserves diversity of interpretation + reduces token cost in the panel prompt).

3. **Reviewer count** - default full slate is 4 distinct heavy reviewers (Claude rubber-duck; GPT, Gemini and Grok code-review). Optional fifth heavy GPT for code-heavy changes. Triage is exactly 2 distinct-family light code-reviewers and requires the same-turn receipt and all fast-path predicates. Full-mode hard-gate panels have a floor of 4 distinct heavy reviewers; triage is the receipt-gated fast path with exactly 2.

4. **Model selection** - pin panel slots to the capability tier and effort in `current-model-registry.md`: full uses `heavy-claude-standard`, `heavy-gpt-premium`, `heavy-gemini-premium`, and `heavy-grok-premium`; optional `heavy-gpt-codex`. Triage uses `light-claude-balanced` + `light-gpt`; use `light-gemini` as a distinct-family fallback. Agents outside panel slots use Auto and the user's `/subagents` settings.

5. **Convergence model** - unanimous for every multi-reviewer panel. Re-review without a round cap until unanimous convergence.

## Optional intake (pre-fillable from upfront input)

7. **Critique focus areas** - when the user has specific concerns (e.g., "focus on the byte-budget feasibility", "verify the ordering claim"), pass these to each reviewer as additional focus points alongside the standard critique focus.

8. **Prior-round-findings sharing** - when iterating rounds, default **share prior findings** with reviewers in subsequent rounds (so they can verify amendments were applied and look for new issues). The user can opt out for a "blind re-review" if they want each round to be independent.

9. **Per-reviewer prompt customization** - when reviewers should bring genuinely different angles, the orchestrator may give each a different critique-focus emphasis (e.g., "fresh-eyes cross-family" vs "technical-design depth" vs "coding-discipline angle"). Defaults to standard differentiation per the model selection above.

10. **Dissent handling** - fixed, not configurable: every NEEDS verdict triggers another round; dissent is never auto-routed (`convergence-models.md`).

11. **Prompt-hygiene pre-dispatch scan (methodology)** - the orchestrator scans the assembled panel prompt for pre-stated conclusions / confirm-the-author language and emits a re-derivable `prompt-hygiene-scan:` disclosure before launch (see `multi-model-review/procedure.md` §"Prompt hygiene (adversarial framing)"). Honest-ceiling disclosure, not a fail-closed gate in this increment.

12. **Author-narrative minimization (diff-target panels)** - default **ON**: the diff-panel framing is built from the raw diff; the author's design narrative is NOT fed as framing, and author assumptions are relocated to the `Author claims to DISPROVE` section (`procedure.md` §"Prompt hygiene (adversarial framing)"). The mandated red-team reviewer (`procedure.md` §"Adversarial red-team reviewer") is the strong form; this applies author-independence to the whole slate's framing. Set OFF only when the artifact cannot be understood from the diff alone (rare; document why).

## Pre-fill rules

- When the user opens with structured detail (e.g., `target=plan.md, model=unanimous`), pre-fill those fields and ask only the unfilled questions.
- Re-confirm overloaded terms before using them in the panel prompts: *team*, *owner*, *scope*, *destination*, *target* are tentative.

## Output

Confirmed intake values fed to `procedure.md` for panel launch.

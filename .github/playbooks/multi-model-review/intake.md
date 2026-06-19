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

3. **Reviewer count** - number of reviewers. Default = the active profile's panel mode (full = **6**: one Claude-family flagship + three GPT-family models for premium / codex / cross-version diversity + one Gemini-family model for third-vendor diversity + one rubber-duck-style critique; lite = **3** cross-family light-tier, >=1 each Claude/GPT/Gemini); if no profile is loaded, default **6** (full-default). Minimum **3** per hard gate (both profiles). Hard-gate convergence stays unanimous on both.

4. **Model selection** - defaults maximize cross-family diversity and reasoning depth. Tier → current model via `current-model-registry.md`:
   - `heavy-claude-xhigh` - Claude family, extra-high reasoning. `code-review` slot.
   - `heavy-gpt-premium` - GPT family, premium reasoning. `code-review` slot.
   - `heavy-gpt-codex` - GPT family, code-specialized. `code-review` slot (different perspective via codex tuning).
   - `heavy-gpt-cross-version` - GPT family, cross-version. `code-review` slot (different reasoning profile from premium).
   - `heavy-gemini-premium` - Gemini family, premium reasoning. `code-review` slot (third-vendor cross-family diversity).
   - **rubber-duck** agent at `heavy-claude-standard` tier - independent design / blind-spot critique (per AGENTS.md sub-agent model selection defaults).

   The user can override individual slots, swap families, or add an additional model when convergence is critical.

5. **Convergence model** - `unanimous` (default; all reviewers verdict DESIGN_READY) / `threshold` (≥75% DESIGN_READY + 0 unaddressed blocking) / `confidence-weighted` (≥80% avg confidence + 0 unaddressed blocking). See `convergence-models.md` for details and selection guidance.

6. **Max-loop count** - default **5**. On exceedance, agent escalates via `ask_user` per the asymptotic-convergence-pattern lesson (do NOT silently loop past max-loop).

## Optional intake (pre-fillable from upfront input)

7. **Critique focus areas** - when the user has specific concerns (e.g., "focus on the byte-budget feasibility", "verify the ordering claim"), pass these to each reviewer as additional focus points alongside the standard critique focus.

8. **Prior-round-findings sharing** - when iterating rounds, default **share prior findings** with reviewers in subsequent rounds (so they can verify amendments were applied and look for new issues). The user can opt out for a "blind re-review" if they want each round to be independent.

9. **Per-reviewer prompt customization** - when reviewers should bring genuinely different angles, the orchestrator may give each a different critique-focus emphasis (e.g., "fresh-eyes cross-family" vs "technical-design depth" vs "coding-discipline angle"). Defaults to standard differentiation per the model selection above.

10. **Asymptotic-convergence behavior** - default **ON**: a sole-NEEDS-reviewer dissent on precise polish (1-2 line fixes, no architectural concern) auto-routes to C2 `routed-deferred` per `convergence-models.md` *Asymptotic-convergence pattern*, with an auto-created session-todo citation. Set OFF when the user wants strict iteration until full convergence (no auto-routing; every NEEDS verdict triggers another round). On panels invoked by `post-code-change.md` (multi-model hard gate), this defaults to OFF - hard-gate panels iterate to unanimous unless the user explicitly authorizes auto-routing.

## Pre-fill rules

- When the user opens with structured detail (e.g., `target=plan.md, model=unanimous, max-loop=5`), pre-fill those fields and ask only the unfilled questions.
- Re-confirm overloaded terms before using them in the panel prompts: *team*, *owner*, *scope*, *destination*, *target* are tentative.

## Output

Confirmed intake values fed to `procedure.md` for panel launch.

# Multi-model review — Intake

Intake questions for `multi-model-review.md`. Bundle independent questions in one `ask_user` prompt; ask sequentially only when a later question depends on an earlier answer.

## Required intake

1. **Review-target type** — what's being reviewed:
   - `plan` — a planning artifact (e.g., `plan.md`, design spec draft, ADO work-item draft).
   - `design` — design doc, current-state survey, architecture proposal.
   - `spec` — interface spec, schema spec, contract spec.
   - `diff` — a code diff (staged, branch-vs-base, or a specific commit range). Default when called by `post-code-change.md` as the panel hard gate.
   - `custom` — user-supplied target; the user provides the focus / scope.

2. **Review-target location** — a file path, branch range, or chat-attached content. Reviewers receive this as a path or reference; each reviewer reads the source independently via `view` / `grep` rather than receiving inline content (preserves diversity of interpretation + reduces token cost in the panel prompt).

3. **Reviewer count** — number of reviewers. Default **5** (one rubber-duck-style critique + two GPT-family models for cross-version diversity + one Claude-family flagship + one code-specialized variant). Minimum **3** per hard gate.

4. **Model selection** — defaults maximize cross-family diversity and reasoning depth:
   - `claude-opus-4.7-xhigh` — Claude family, extra-high reasoning. `code-review` slot.
   - `gpt-5.5` — OpenAI family, premium reasoning. `code-review` slot.
   - `gpt-5.3-codex` — OpenAI family, code-specialized. `code-review` slot (different perspective from gpt-5.5 via codex tuning).
   - `gpt-5.4` — OpenAI family, cross-version. `code-review` slot (different reasoning profile from gpt-5.5).
   - **rubber-duck** agent with `model: 'claude-opus-4.8'` — independent design / blind-spot critique (Opus-level reasoning per AGENTS.md sub-agent model selection defaults).

   The user can override individual slots, swap families, or add a 6th+ model when convergence is critical.

5. **Convergence model** — `unanimous` (default; all reviewers verdict READY) / `threshold` (≥75% READY + 0 unaddressed blocking) / `confidence-weighted` (≥80% avg confidence + 0 unaddressed blocking). See `convergence-models.md` for details and selection guidance.

6. **Max-loop count** — default **5**. On exceedance, agent escalates via `ask_user` per the asymptotic-convergence-pattern lesson (do NOT silently loop past max-loop).

## Optional intake (pre-fillable from upfront input)

7. **Critique focus areas** — when the user has specific concerns (e.g., "focus on the byte-budget feasibility", "verify the ordering claim"), pass these to each reviewer as additional focus points alongside the standard critique focus.

8. **Prior-round-findings sharing** — when iterating rounds, default **share prior findings** with reviewers in subsequent rounds (so they can verify amendments were applied and look for new issues). The user can opt out for a "blind re-review" if they want each round to be independent.

9. **Per-reviewer prompt customization** — when reviewers should bring genuinely different angles, the orchestrator may give each a different critique-focus emphasis (e.g., "fresh-eyes cross-family" vs "technical-design depth" vs "coding-discipline angle"). Defaults to standard differentiation per the model selection above.

10. **Asymptotic-convergence behavior** — default **ON**: a sole-NEEDS-reviewer dissent on precise polish (1–2 line fixes, no architectural concern) auto-routes to C2 `routed-deferred` per `convergence-models.md` *Asymptotic-convergence pattern*, with an auto-created session-todo citation. Set OFF when the user wants strict iteration until full convergence (no auto-routing; every NEEDS verdict triggers another round). On panels invoked by `post-code-change.md` (multi-model hard gate), this defaults to OFF — hard-gate panels iterate to unanimous unless the user explicitly authorizes auto-routing.

## Pre-fill rules

- When the user opens with structured detail (e.g., `target=plan.md, model=unanimous, max-loop=5`), pre-fill those fields and ask only the unfilled questions.
- Re-confirm overloaded terms before using them in the panel prompts: *team*, *owner*, *scope*, *destination*, *target* are tentative.

## Output

Confirmed intake values fed to `procedure.md` for panel launch.

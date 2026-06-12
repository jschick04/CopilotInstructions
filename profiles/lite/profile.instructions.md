---
applyTo: "**/*"
---
<!-- profile-id: lite -->

# Active profile: lite

Parameterizes the review workflow for reduced token usage (personal / paid-token work: smaller, lighter panels). The active profile is whichever `profile.instructions.md` the install script copied to `.github/instructions/active-profile.instructions.md` (per-machine, gitignored). Select with `setup.ps1 -Profile lite` / `setup.sh --profile lite`. Runtime authority is this loaded file's profile-id; `invoke-panel.ps1` also reads it on-disk to enforce the panel floor. This file holds parameters only; the rules live in `panel-policy.md` and `review-workflow-gates.md`.

- Default panel mode: `lite` (3 reviewers; >=1 Claude + >=1 GPT + >=1 Gemini family; light-tier per `multi-model-review/current-model-registry.md`: light-claude-balanced + light-gpt + light-gemini; >=1 rubber-duck + >=2 code-review; unanimous convergence; max-loop 5 as usual).
- Trivial fast-path: sanctioned `triage` mode (1 reviewer + `triage-acknowledged` receipt) ONLY when ALL hold: (a) not a governance/instruction artifact (any repo); (b) not safety-critical (`workflow-conventions.md` §5); (c) only docs/`.md` files OR changed_lines_total < 10 (added+removed non-blank, non-rename-only, across the whole diff) with no control-flow / public-API / concurrency change. Any miss or any uncertainty -> escalate to `lite` (3) or `full`.
- Output: minimal (prefer the most compact KV forms; suppress optional narration). High-risk gate blocks stay verbose.
- Safety-critical and governance/instruction artifacts: full slate always; never any fast-path (same on both profiles).
- A mode below this profile's floor (`triage`, `lint-only`) requires that mode's ask_user receipt; `lite` mode at floor needs none (the install-time `-Profile lite` is the standing choice).
- Emit `profile=lite` in the POST-CODE-CHANGE LEDGER, PRE-COMMIT GATE PASSED, and PANEL CONVERGED blocks.

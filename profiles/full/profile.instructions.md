---
applyTo: "**/*"
---
<!-- profile-id: full -->

# Active profile: full

Parameterizes the review workflow. The active profile is whichever `profile.instructions.md` the install script copied to `.github/instructions/active-profile.instructions.md` (per-machine, gitignored). If no active profile is loaded, behavior is `full-default` (identical to full). Select with `setup.ps1 -Profile full` / `setup.sh --profile full`. This file holds parameters only; the rules live in `panel-policy.md` and `review-workflow-gates.md`.

- Default panel mode: `full` (4-6 reviewers per the `panel-policy.md` full slate floor: >=1 Claude + >=2 GPT + >=1 Gemini family, >=1 rubber-duck + >=2 code-review, >=1 heavy-tier).
- Trivial fast-path: not sanctioned on full. `triage` / `lint-only` require their usual explicit CLI flag + ask_user receipt.
- Hard-gate convergence: unanimous.
- Output: standard (compressed-KV low-risk records per `review-workflow-gates-sweeps.md` §2B; verbose high-risk gate blocks).
- Safety-critical and governance/instruction artifacts: full slate always; never any fast-path (same on both profiles).
- Emit `profile=full` in the POST-CODE-CHANGE LEDGER, PRE-COMMIT GATE PASSED, and PANEL CONVERGED blocks.

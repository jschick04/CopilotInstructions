# Playbook: Instruction-set maintenance
<!-- read-receipt-token: 9b6c4476 -->

## When this applies

Editing ANY file in the instruction-set repo. Non-exhaustive: `AGENTS.md`, `.github/copilot-instructions.md` (if present), `.github/instructions/**`, `.github/playbooks/**`, `.github/pr-quality-gate/**`, `profiles/**`, `scripts/**`, `.github/workflows/**`, `.githooks/**`, `.gitattributes`, `.gitignore`, `setup.ps1`/`setup.sh`. All such edits are governance/safety-critical -> **full review rigor on both profiles** (never lite/triage/lint-only, never the trivial-PR carve-out), per the AGENTS.md governance rule.

## Core principles (the preferences this set is maintained by)

1. **Universal set - NO project-specific references.** These instructions are installed into ANY project. No project names, no project-specific domain types, no PR numbers, no product specifics. Examples use language-generic, illustrative names (Order, Customer, Widget, Foo/Bar). Provenance is recorded generically ("from a consuming-project PR review"), never a project name or PR number.
2. **Minimize always-loaded context.** Principle -> `AGENTS.md` (terse). Procedure/detail -> on-demand playbook. Language-specific -> the language instruction file (applyTo-scoped, loads only for matching files). Universal-code -> `coding-standards-code` (loads on any code edit). Universal-all-files -> `coding-standards` (applyTo `**/*`). Never put language/project specifics in a universal file. Split detail to a playbook once an `AGENTS.md` addition would exceed ~10 lines / ~1.5KB.
3. **DRY - define once, point elsewhere.** A rule/grammar/schema has ONE home; every other mention is a pointer to it. Prevents drift and saves bytes.
4. **Forcing functions are sacred.** When compressing FORM (verbose -> KV/caveman), preserve every enumeration, metric, and key-presence gate. Compress structure, never the gate.
5. **Catalog-first (zero-repeats).** EVERY generalizable review finding becomes a `pattern-catalog` slug immediately - do NOT wait for a recurrence. The catalog is the auto-detection battery; a finding only cataloged after it repeats has already cost a second miss. The complementary half: log each gate-miss to `panel-misses.csv` (feeds the anti-recidivism preamble). The goal is that no project hits the same class of issue twice.

## Placement decision table

| Content kind | Home | Loads when |
|---|---|---|
| Principle (1-3 sentences) | `AGENTS.md` | always |
| Universal, all file types | `coding-standards.instructions.md` (applyTo `**/*`) | always |
| Universal, code only | `coding-standards-code.instructions.md` | any code edit |
| Language-specific | `<lang>.instructions.md` (applyTo `**/*.<ext>`) | that language only |
| Procedure / detailed steps | on-demand playbook (`.github/playbooks/**`) | when fetched per the router |
| EVERY generalizable review finding (catalog-first) | `pattern-catalog` slug via the source pipeline (see "Catalog edits") | gate-runner / panel |

## Catalog edits (generated from sources - never hand-edit the flat file)

`pattern-catalog.md` is GENERATED; editing it by hand fails `.github/workflows/catalog-generator-check.yml`. The flow:
1. Edit the source(s) under `.github/pr-quality-gate/pattern-catalog.sources/**`.
2. Regenerate the flat catalog: `pwsh -File scripts/generate-pattern-catalog.ps1`.
3. Verify sync: `pwsh -File scripts/verify-pattern-catalog.ps1`.
4. Regenerate the derived ack index: `pwsh -File scripts/sync-critical-rules.ps1` (updates `HIGH-TIER-SLUGS.md`; `.githooks/pre-commit` + `.github/workflows/catalog-sync-check.yml` enforce sync).
5. The user stages the reviewed source(s); the agent stages the generated `pattern-catalog.md` + `HIGH-TIER-SLUGS.md` (artifacts) - regenerated only when the source has no unstaged delta.

**Slug quality bar (every slug must clear this; existing catalog entries are the floor):** name (a) the specific code pattern checked, (b) the specific failure mode, (c) the specific verification step, and (d) a bright-line PASS/FAIL criterion - enough that a reviewer can give a definitive per-site answer on a diff. Mechanically-detectable findings get a regex/audit method; judgment findings get a `review_pass_only_prompt` that meets (a)-(d). A vague prompt ("review X for issues") is REJECTED - it bloats `core_rules_acknowledged` with un-citable sites (checkbox theater).

The CI checks (`.github/workflows/catalog-generator-check.yml`, `.github/workflows/catalog-sync-check.yml`) are the fail-closed backstop; never hand-edit `pattern-catalog.md` to bypass the pipeline.

## No project-specific references (hard rule + audit)

- Forbidden in committed instruction content: project names, project-specific type/identifier names, PR/issue numbers, product/domain specifics.
- Examples must be language-generic and self-evidently illustrative.
- **Pre-commit audit (advisory until Batch B2):** scan the staged diff for the current consuming-project identifiers - `git diff --cached -U0 | grep -nEi '<project-name>|<product-name>|<project-specific-type-or-namespace>' | grep -v '^\+\+\+'` (replace the `<...>` tokens with the actual identifiers before running) - 0 hits required. Until Batch B2 wires the per-deployment denylist config + the `project-refs-leakage` rg-battery check, the ENFORCED gate is the full-rigor panel review on every instruction-repo diff; this grep is an advisory pre-check.
- Provenance / "why this rule exists": phrase generically. A lesson learned from a consuming project's PR review is recorded as "from a consuming-project PR review", not the project name.
- Exception: the `data/panel-misses.csv` `pr_ref` column keeps its deidentified ledger keys (functional anti-recidivism identifiers in the machine ledger, not copied into instruction examples); the ledger is excluded from the B2 denylist scan scope.

## The edit cycle (full rigor)

1. **Draft the spec** (in the session folder, not the repo).
2. **Rubber-duck** (Stage-1 single critical pass).
3. **Panel** (Stage-2): the full slate per `panel-policy.md` (4-6 reviewers, >=3 model families); iterate to **unanimous** convergence; emit the `PANEL CONVERGED` certification BEFORE any repo edit (§1B in `review-workflow-gates.md`).
4. **Implement** against the converged spec. Canonical schemas stay; add caveman chat-emission forms separately (canonical-vs-chat split). RE-MEASURE caps.
5. **Diff-review panel** (all reviewers on the actual diff) -> unanimous READY.
6. **§0 commit gates** -> PR-based workflow.

## Caps & measurement

- `AGENTS.md` <= 28672 B; non-exempt `.github/**/*.md` <= 30720 B; `profiles/**/*.md` <= 4096 B. Exempt: `pattern-catalog.md` (allowlisted - a GENERATED data file, not prose to split) and `pattern-catalog.sources/**` (excluded). (Token-aware caps planned.)
- Measure **LF** bytes, e.g. for a path in `$f`: ``[System.Text.Encoding]::UTF8.GetByteCount(((Get-Content -Raw $f) -replace "`r`n","`n"))``. Local working copies are CRLF and over-count; `.gitattributes` normalizes to LF on commit; CI measures LF.
- Enforced by `.github/workflows/instructions-size-check.yml`.

## Conventions checklist (apply on every edit)

- **No banned smart punctuation** (§3.14): defer to `AGENTS.md` §3.14 for the full banned set (em/en-dashes, smart quotes, ellipsis, horizontal bar); plain symbols like `§` are fine. Scan added diff lines.
- **Canonical-vs-chat split**: the audit-file/CI-consumed schema stays; chat emits the compressed caveman form defined in a separate subsection.
- **Read-receipt tokens**: preserve the `read-receipt-token` HTML-comment marker near the top of files that carry one.
- **Comments**: structural section banners only; no narrative code comments without the §3.1 gate.
- **Commit**: author per `AGENTS.md` §4 (human identity, not an automation identity); single-line imperative subject; no body/footer; no `Co-authored-by` trailer; no Conventional-Commit prefix.
- **Active profile**: edit the git-tracked `profiles/<full|lite>/profile.template.md` templates, NEVER the gitignored generated `.github/instructions/active-profile.instructions.md` (the harness loads it; `invoke-panel.ps1` reads it as the floor). Re-run setup to regenerate.

## Updating after reviewing PR comments on GitHub

Source of many instruction updates: review comments (human + the Copilot review bot) on a consuming project's PR reveal a gap the instructions should have caught.

1. **Collect** the review comments on the PR: `gh pr view <n> --comments` for the conversation + `gh api repos/{owner}/{repo}/pulls/<n>/comments` for inline review threads.
2. **Triage** each comment: confirm the lesson is generalizable beyond this one project (almost always yes once stripped of specifics).
3. **Generalize** the lesson: strip ALL project-specifics (names, types, PR numbers) down to the universal rule.
4. **Catalog EVERY finding (catalog-first).** Add a `pattern-catalog` slug for each generalizable finding via the source pipeline (see "Catalog edits"), meeting the slug quality bar - do NOT wait for a recurrence; the goal is ZERO repeats. Then place any broader rule per the placement table. Only a genuinely project-unique AND non-generalizable finding is exempt (rare; document why in the commit).
5. **Log the gate-miss.** Record each finding the gate SHOULD have caught to `.github/pr-quality-gate/data/panel-misses.csv` (`pwsh -File scripts/Add-PanelMissesRow.ps1`) so the `anti_recidivism_acknowledged` preamble re-checks it on later rounds of the same PR.
6. **Run the edit cycle** (full rigor above).
7. **Record provenance generically** in the commit/notes ("from a consuming-project PR review"), never the project name or PR number.

## Workflow

- **PR-based** (no direct-push-to-main): branch -> commit -> push -> `gh pr create` -> required checks + bot review -> merge. CI checks: always-on (`catalog-sync-check`, `pr-gate-check` comment-audit) + path-filtered (`instructions-size-check`, `catalog-generator-check`, `profile-invariants-check`, run only when their paths change).
- Commit-authoring and §0 git gates per `AGENTS.md` §0/§4.

## Profiles

- `full` (default; full panel) and `lite` (reduced panel) selected by the installer: `.\setup.ps1 -Profile <full|lite>` / `./setup.sh --profile <full|lite>`. Governance/instruction + safety-critical edits use full rigor on BOTH profiles. See `profiles/` + `panel-policy.md`.

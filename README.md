# CopilotInstructions

Personal Copilot CLI custom instructions, split into a slim always-loaded core (`AGENTS.md`), conditionally-loaded topic files (one per language), and **on-demand playbook files** that the agent fetches when entering a workflow phase or when a strong-trigger intent is detected and the user confirms via `ask_user`. The system serves two primary use cases — (1) the **change-implementation pipeline** (pre-implementation → post-code-change → pre-commit → pre-PR-push → post-PR-review) shipping code changes through a multi-model reviewer panel, and (2) **investigative workflows on unchanged code** (cross-file bug hunting, architectural debt audits, visibility audits) — plus various other strong-trigger playbooks for design specs, ADO planning, worktree setup, library restructure, and similar tasks (see the *Workflows at a glance* table below for the full catalogue). Optimized for context-window usage — language-specific style guidance only loads when the working set contains that language, and heavy multi-step procedural detail only loads when the agent reaches the relevant phase or playbook.

## Layout

```
CopilotInstructions/
├── AGENTS.md                                           # always loaded — phase index + hard gates + universal coding standards (§3) + commit messages (§2) + ask-first / skip / state-tracking rules
├── .github/
│   ├── instructions/                                   # auto-loaded conditionally by applyTo glob
│   │   ├── csharp.instructions.md                      # C# / Razor / .NET
│   │   ├── cpp.instructions.md                         # C / C++
│   │   ├── javascript-typescript.instructions.md       # JS / TS
│   │   ├── html.instructions.md                        # HTML / Razor / cshtml markup
│   │   └── css.instructions.md                         # CSS / SCSS / SASS / LESS
│   └── playbooks/                                      # NOT auto-loaded — agent fetches on demand per phase / trigger
│       ├── README.md                                   # folder convention + required playbook structure (frontmatter / Purpose / Hard gates / Intake / Procedure) + evidence-gate / manifest / multi-model-review cross-reference
│       ├── manifest.yaml                               # discoverability index — generated/derived from playbook frontmatter; consulted AFTER router shortlists; never drives initial detection
│       ├── pre-implementation.md                       # deepened diagnose + G3 approach-selection + G5 safety-critical-skip + rubber-duck (phase)
│       ├── post-code-change.md                         # hygiene + LPA + recurring-pattern sweep + §3.1 comment audit gate + multi-model-review (utility) + verify-the-fix + builds/tests (phase)
│       ├── pre-commit.md                               # diff approval + commit hygiene (phase)
│       ├── pre-pr-push.md                              # INDEX — runs intake then dispatches to sub-files (phase)
│       ├── pre-pr-push/                                # heaviest phase playbook split into 4 sub-files
│       │   ├── per-commit-micro-hygiene.md
│       │   ├── branch-wide-sweep.md
│       │   ├── cleanup-commit-buckets.md               # natural-unit grouping default (G2) + 3 cleanup buckets + staging-sprawl guard
│       │   └── when-to-re-run-sweep.md
│       ├── post-pr-review.md                           # bot-finding audit + C2 status enum + instructions delta (phase)
│       ├── worktree-setup.md                           # hidden-bare + sibling-checkouts layout + stacked-worktree-for-stacked-PR discipline (G7)
│       ├── software-install.md                         # platform-package-manager-first install + fallbacks
│       ├── design-spec.md                              # current-state survey / design-change request / dev design spec (durable artifact)
│       ├── ado-task-planning.md                        # ADO work-item content (markdown summary + ADO-field block)
│       ├── library-restructure.md                      # VSA topology + growth planning + de-duplication
│       ├── least-privilege-audit.md                    # 6-axis index — fires from post-code-change (touched) / pre-pr-push (branch-wide) / strong trigger
│       ├── least-privilege-audit/                      # 6 axis sub-files (Axis 1 hosts G6 dead-code default-delete with exported-API + predicate-field carve-outs)
│       │   ├── axis-1-type-access.md
│       │   ├── axis-2-sealing-finality.md
│       │   ├── axis-3-ctor-visibility.md
│       │   ├── axis-4-member-visibility.md
│       │   ├── axis-5-setter-visibility.md
│       │   └── axis-6-field-hygiene.md
│       ├── scope-planning.md                           # light planning before any code (problem / users / success / scope / constraints)
│       ├── project-vocabulary.md                       # per-repo vocabulary doc bootstrap / refresh
│       ├── implementation-planning.md                  # deep codebase-aware planning for a specific code change; output feeds pre-implementation
│       ├── system-framing.md                           # symbol → module → assembly → product surface map
│       ├── intent-driven-testing.md                    # phase-sub-step — operationalizes §3.4 (prospective in pre-impl, retrospective in post-code-change)
│       ├── codebase-architecture-audit.md              # 5-lens read-only audit index (NOT a durable design doc)
│       ├── codebase-architecture-audit/                # 5 lens sub-files for §3.7 / §3.8 / §3.10 / §3.11 / §3.12
│       │   ├── lens-state-predicates.md
│       │   ├── lens-deferred-mutations.md
│       │   ├── lens-recurring-smells.md
│       │   ├── lens-project-layout.md
│       │   └── lens-vertical-slice-clean-arch.md
│       ├── cross-file-bug-investigation.md             # panel-driven cross-file bug hunt on UNCHANGED code (index)
│       ├── cross-file-bug-investigation/               # lane catalog sub-file (9 lanes per M17 schema)
│       │   └── lanes-catalog.md
│       ├── design-exploration.md                       # throwaway prototype (design alternatives / UI variations)
│       ├── performance-comparison.md                   # throwaway benchmark prototype + mandatory software-install.md handoff
│       ├── multi-model-review.md                       # panel-of-reviewers convergence (index) — domain trigger + utility-called by post-code-change
│       ├── multi-model-review/                         # 9 panel support files (intake + procedure + convergence-models + evidence-gate-spec + 5 catalog/registry files)
│       │   ├── intake.md                              # 10 intake questions + model defaults
│       │   ├── procedure.md                           # parallel-launch + sub-agent prompt template (incl. bug-investigation target-type)
│       │   ├── convergence-models.md                  # unanimous / threshold ≥75% / confidence-weighted ≥80% + asymptotic-convergence pattern
│       │   ├── evidence-gate-spec.md                  # per-round log + C2 audit + bug-investigation extensions
│       │   ├── current-model-registry.md              # tier → model name mapping (decouples playbooks from model deprecations)
│       │   ├── known-false-positives.md               # dismissed-source-grounded patterns reviewers should NOT re-flag
│       │   ├── pr-creation-mirror-prompt.md           # 11-category Copilot-mirror prompt template for §2D pre-pr-creation panel
│       │   ├── pr-review-findings-schema.md           # schema for PR-bot findings → pattern-catalog
│       │   └── pr-review-pattern-catalog.md           # PR-review-derived pattern catalog (input to pattern-catalog.md)
│       └── templates/                                  # skeleton / example reference files
│           ├── current-state-survey.md
│           ├── design-change-request.md
│           └── dev-design-spec.md
├── pr-quality-gate/                                    # catalog + ack-gate + drift safeguard (rule enforcement during code review)
│   ├── pattern-catalog.md                              # canonical rule catalog (116 data rows; 47 HIGH-tier slugs requiring per-commit ack)
│   ├── HIGH-TIER-SLUGS.md                              # GENERATED — derived from pattern-catalog.md; ack-required slug list
│   ├── panel-policy.md                                 # convergence model + per-rule ack schema + catalog-edit invariant
│   ├── gate-runner.ps1 / .sh                           # rg battery runner (cross-platform; pwsh + bash twins, parity-checked)
│   ├── invoke-panel.ps1                                # panel launcher with mode-receipt validation
│   └── data/                                           # findings + panel-miss telemetry (project-deidentified)
├── scripts/
│   ├── sync-critical-rules.ps1 / .sh                   # regen HIGH-TIER-SLUGS.md from pattern-catalog.md (byte-identical twins)
│   ├── Add-PanelMissesRow.ps1                          # RFC 4180-compliant CSV appender
│   └── migrate-panel-misses-csv.ps1
├── .githooks/
│   └── pre-commit                                      # NEW — POSIX shell hook; verifies HIGH-TIER-SLUGS.md stays in sync with pattern-catalog.md; mode 100755
├── .github/workflows/
│   └── catalog-sync-check.yml                          # NEW — CI backstop; verify + parity jobs on every push/PR
├── .gitattributes                                      # NEW — `* text=auto` for LF normalization across platforms
├── README.md                                           # this file
├── setup.ps1                                           # one-time configuration helper (Windows; configures env var + core.hooksPath)
└── setup.sh                                            # NEW — Unix equivalent of setup.ps1
```

## How loading works

The Copilot CLI loads custom instructions from several documented locations. This repo uses the `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` environment variable, which is a **comma-separated** list of directories. For each listed directory the CLI looks for:

- `AGENTS.md` (loaded as additional always-on instructions for every session).
- `.github/instructions/**/*.instructions.md` (each file is conditionally loaded based on the `applyTo:` glob in its YAML frontmatter).

`.github/playbooks/**/*.md` is **NOT** auto-loaded by the CLI — those files are fetched on demand by the agent when `AGENTS.md` directs it (e.g. *"STOP. Before this phase, view `.github/playbooks/post-code-change.md`."*) or when the agent detects a strong-trigger intent (artifact requested — *"design spec"*, *"draft an ADO task"*) and the user confirms via `ask_user`. This is what keeps the always-loaded prompt tax small while still letting heavy procedural detail be available when needed.

**Fail-closed on fetch failure.** If a required playbook can't be fetched (file missing / unreadable / agent has no working-set access), the corresponding phase is **not** considered complete. Per `AGENTS.md` *Fail-closed rule for on-demand playbook fetch*: retry the fetch once for transient errors; if it still fails, ask the user via `ask_user` how to proceed; record an explicit user skip per the User-skip policy ONLY if the user explicitly authorizes one. Do NOT retry more than once without user input. Do NOT proceed using only the abbreviated hard-gate checklists in `AGENTS.md` as the procedure — those checklists confirm the gate, the playbook teaches the procedure.

Pointing `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` at this cloned repo makes every edit here live in the next CLI session — no separate sync to `~/.copilot/` is required.

### `applyTo` glob table

| File | `applyTo` globs |
| --- | --- |
| `csharp.instructions.md` | `**/*.cs`, `**/*.csx`, `**/*.csproj`, `**/*.razor`, `**/*.razor.cs`, `**/*.cshtml`, `**/*.aspx` |
| `cpp.instructions.md` | `**/*.cpp`, `**/*.h`, `**/*.hpp`, `**/*.cc`, `**/*.cxx`, `**/*.c` |
| `javascript-typescript.instructions.md` | `**/*.ts`, `**/*.tsx`, `**/*.mts`, `**/*.cts`, `**/*.js`, `**/*.jsx`, `**/*.mjs`, `**/*.cjs` |
| `html.instructions.md` | `**/*.html`, `**/*.htm`, `**/*.razor`, `**/*.cshtml` |
| `css.instructions.md` | `**/*.css`, `**/*.scss`, `**/*.sass`, `**/*.less` |

Razor markup files (`*.razor`, `*.cshtml`) intentionally match both the C# file (for codebehind / `@code` blocks) and the HTML file (for markup syntax).

## PR quality gate (catalog + ack + drift safeguard)

Beyond the playbooks (which are procedural), this repo provides a **rule enforcement gate** that runs during code review. The gate has four layers (defense in depth):

1. **Catalog of rules** — `.github/pr-quality-gate/pattern-catalog.md` lists **116 patterns** (HIGH/MEDIUM/LOW tier; **47 HIGH-tier slugs require per-commit acknowledgement** in the `core_rules_acknowledged` block per `panel-policy.md` §Per-rule acknowledgement; cycles 1-4 raised HIGH slugs 24→47) the multi-model panel checks against every commit's diff. Rules are either **rg-detectable** (deterministic regex) or **review-pass-only** (panel reviewer reads the diff against an audit-method clause).
2. **Per-rule acknowledgement** — for every HIGH-tier `review-pass-only` slug, every commit MUST emit a `core_rules_acknowledged` block enumerating each slug with per-site disposition (`applied` / `not-applicable` + rationale). The generated `HIGH-TIER-SLUGS.md` is the authoritative ack-required list; the panel and pre-commit gate cross-reference it.
3. **Process-rule gates** — some catalog rules check process artifacts rather than code: e.g., `least-privilege-audit-required-on-visibility-delta` and `intent-driven-testing-required-on-test-or-SUT-delta` verify the POST-CODE-CHANGE LEDGER block has the matching playbook-evidence field. This is how the LPA and ITD playbooks fire automatically (not just on user strong-trigger).
4. **Drift safeguard** — git pre-commit hook + CI workflow + gate-runner `-Verify` integration prevent `HIGH-TIER-SLUGS.md` from going stale relative to `pattern-catalog.md`. Mechanism uses `git hash-object` (canonical normalized blob SHA-1; cross-platform stable, immune to CRLF/LF drift).

**Canonical sources** (this README is overview-only):
- `panel-policy.md` — convergence model, per-rule ack schema, catalog-edit + ack-sync invariant
- `review-workflow-gates.md` — POST-CODE-CHANGE LEDGER §2B canonical format
- `pattern-catalog.md` — full rule definitions with audit methods

## Consumer-repo adoption — comment-protocol persisted audit + CI gate

When a downstream consumer repo adopts these instructions and wants the §3.1 comment-protocol's server-side enforcement (per `.github/playbooks/comment-protocol.md` §Persisted audit file), the consumer needs to copy the following into its own repo (one folder, one workflow file, and four script files — six file-level artifacts total grouped into three numbered items below):

1. **`.github/pr-quality-gate/audits/` folder** — create the directory and add a `.gitkeep` (so the folder exists before the first commit writes `last.md`). Per-commit, the agent writes `last.md` here containing the §2.6 audit block + `parent_sha:` header.

2. **`.github/workflows/pr-gate-check.yml`** — copy the workflow file from this instructions repo as-is. The workflow runs `./scripts/check-comment-audit.ps1` and `./scripts/check-playbook-refs.ps1` against PRs targeting `main` (rename `branches: [main]` if the consumer repo's default branch is different).

3. **`scripts/check-comment-audit.ps1` + `scripts/check-playbook-refs.ps1` + `scripts/lib/comment-audit-helpers.psm1` + `scripts/tests/check-comment-audit.tests.ps1`** — copy all four artifacts from this instructions repo. The CLI wrapper `check-comment-audit.ps1` imports the module from `lib/comment-audit-helpers.psm1`; without the module file, the CLI exits `INVOCATION_FAILED` immediately. The workflow's `script-tests` job runs the test file unconditionally — without it, CI fails. The scripts have no instructions-repo-specific hardcoded paths; they work from any project root that has `.git`, a `.github/playbooks/` folder (for the ref-check job), and the `.github/pr-quality-gate/audits/last.md` convention. If you do NOT want the `script-tests` CI job, delete that job stanza from the copied workflow.

**Default branch override** — if the consumer's default branch is not `main`, edit the workflow's `branches: [main]` filter. The `BaseRef` is derived dynamically from `${{ github.base_ref }}` inside the workflow's `run:` block — no separate argument edit is needed.

**Bootstrap commit** — the FIRST commit in the adoption PR that adds `.github/pr-quality-gate/audits/last.md` is detected as the bootstrap commit (`scripts/check-comment-audit.ps1` skips ledger verification for that single commit only). **Best practice:** make this commit the very first commit in the adoption PR and ALSO commit an initial `audits/last.md` file with the bootstrap disposition (use this repo's `.github/pr-quality-gate/audits/last.md` as a template). Subsequent commits in the same PR are verified normally — they MUST stage an updated `last.md` per commit. (Without this practice, an adopter who only commits `.gitkeep` in PR 1 creates a 2-PR gap: PR 1 skips bootstrap, PR 2's first add of `last.md` is also detected as bootstrap, so enforcement starts on PR 3.)

**No `.github/playbooks/` folder?** — `check-playbook-refs.ps1` exits with INVOCATION_FAILED if the folder is missing. Either create an empty `.github/playbooks/.gitkeep` to satisfy the precondition or remove the `playbook-ref-check` job from the workflow.

## Catalog rule lifecycle

```
pattern-catalog.md (canonical source)
       │
       │  scripts/sync-critical-rules.ps1  (pwsh)
       │  scripts/sync-critical-rules.sh   (bash twin, byte-identical output)
       ▼
HIGH-TIER-SLUGS.md (generated — listed slugs require per-commit ack)
```

Both generators embed `git hash-object .github/pr-quality-gate/pattern-catalog.md` as the content hash in the output header. `git hash-object` is git's canonical normalized blob SHA-1, immune to working-tree CRLF/LF drift. `.gitattributes` (`* text=auto`) ensures consistent normalization on commit.

**Enforcement layers** (panel-policy.md §"Catalog-edit + ack-sync invariant"):
1. `.githooks/pre-commit` — local enforcement at moment-of-edit. Triggers on `pattern-catalog.md` OR `HIGH-TIER-SLUGS.md` staged. Uses `git show :path` to verify the staged index (not working tree).
2. `setup.ps1` (Windows) / `setup.sh` (Unix) — wire `core.hooksPath .githooks` for new clones. Existing contributors run one of these once per clone.
3. `gate-runner.ps1` / `.sh` + `invoke-panel.ps1` — panel-time secondary check (catches stale clones).
4. `.github/workflows/catalog-sync-check.yml` — CI backstop (catches `git commit --no-verify` bypass + contributors who never ran setup). Two jobs: `verify` (HIGH-TIER-SLUGS in sync) + `parity` (pwsh and bash generators produce byte-identical output).

To add a new rule: edit `pattern-catalog.md`, run `pwsh -File scripts/sync-critical-rules.ps1`, stage both files. The pre-commit hook verifies.

## Playbook integrations

The four initial cycle-1 / cycle-2 in-repo playbook integrations are shown below (cycle 3 expanded enforcement to 7 cycle-3-scope playbooks at the pre-implementation phase — including 2 of the four below that gained additional cycle-3 rules — see *Phase-by-phase playbook map* below for the complete current state). These four fire automatically during commit / panel review, not just when explicitly user-triggered:

| Playbook | Enforcement engine | Catalog rule(s) |
|---|---|---|
| `least-privilege-audit.md` | commit-time ledger gate (POST-CODE-CHANGE LEDGER `touched-file-LPA` field) | `least-privilege-audit-required-on-visibility-delta` (HIGH) |
| `intent-driven-testing.md` | commit-time ledger gate (POST-CODE-CHANGE LEDGER `intent-driven-testing-audit` field) + reviewer pass for §3.4 Direction A check | `intent-driven-testing-required-on-test-or-SUT-delta` (HIGH) + `test-without-direction-A-regression-pin` (MEDIUM) |
| `design-exploration.md` | rg battery (`prototype-imported-by-production`) + reviewer pass (marker check) | `prototype-imported-by-production` (HIGH, tree-scoped rg) + `prototype-file-missing-throwaway-marker` (MEDIUM) |
| `performance-comparison.md` | inherits design-exploration rules + reviewer pass (quantitative-claim check) | the two prototype rules above + `perf-claim-without-environment-capture` (MEDIUM) |

The ledger-gate rules (LPA, ITD) work by requiring evidence in the agent's POST-CODE-CHANGE LEDGER block (canonical schema in `review-workflow-gates.md` §2B). Reviewers verify the field is populated when the diff's trigger condition holds. `N/A — <reason>` values must cite a specific carve-out from the playbook (framework-mandated visibility, rename-only test delta, etc.) — bare `N/A` is a violation.

The rg-rule (`prototype-imported-by-production`) is `tree-scoped` and uses a multi-language import-statement regex (C#, TS/JS, Python, Rust, Go, Java/Kotlin, C++) with word-boundary anchoring to avoid `myprototypes`/`prototypes2` false positives. Excludes the prototype subtree itself via `--glob '!prototypes/**'`.

## Phase-by-phase playbook map

Cycle-3 expanded catalog enforcement to 7 cycle-3-scope playbooks at the pre-implementation phase (G6 step in `pre-implementation.md`) PLUS 2 post-impl gap-fill rules. Combined with cycle-1/2 enforcement, the map per phase is:

| Phase | Auto-invoked | Required-on-trigger | Offered-on-trigger | Referenced |
|---|---|---|---|---|
| Pre-implementation | `multi-model-review` panel (target-type `plan`); G5 + G6 evaluations | `implementation-planning` (non-trivial change), `library-restructure` (folder/namespace move) | `design-exploration` (≥2 competing approaches), `performance-comparison` (quantitative perf goal), `scope-planning` (scope <50 chars + no artifact), `system-framing` (cross-asm/project boundary), `project-vocabulary` (≥3 new domain terms) | `solution-architecture` (informational), `design-spec`, `ado-task-planning` |
| Implementation | `intent-driven-testing` (prospective — when `behaviors_to_cover` non-empty) | (catalog meta-rule `implementation-phase-missed-playbook-required-by-pre-impl` verifies the 4 in-scope decision-having playbooks were honored per pre-impl LEDGER decisions) | | `software-install` (as needed) |
| Post-code-change | `least-privilege-audit` (touched-file scope), `intent-driven-testing` (retrospective), `multi-model-review` panel, recurring-pattern sweep, prior-PR-review sweep, DRY-audit, §3.1 comment audit | (post-impl rules `library-restructure-required-on-folder-namespace-move-in-diff` HIGH + `implementation-planning-required-on-nontrivial-final-diff` HIGH catch missed-re-entry bypasses) | | |
| Pre-commit | (consumes POST-CODE-CHANGE LEDGER incl. `pre-impl-trigger-detections` + `pre-impl-playbook-decisions` + `playbook-invocations` sub-blocks per `review-workflow-gates.md` §2B) | | | |
| Pre-PR-creation | `pre-pr-creation-review` heavy panel (Delta-G sweeps, 11-category mirror prompt) | | | |
| Pre-PR-push | `least-privilege-audit` (branch-wide scope), `per-commit-micro-hygiene`, `branch-wide-sweep`, prior-PR-review sweep | | | |
| Post-PR-review | bot-finding audit + C2 status enum + instructions delta | | | |

**REQUIRED-decision-recorded vs OFFERED classes** (cycle-3 G6 decision-value semantics):

- **REQUIRED-decision-recorded class** (`implementation-planning`, `library-restructure`): when G6 detects the trigger, the LEDGER decision MUST be `invoked` OR `required-but-skipped: "<safety-critical re-confirmation per User-skip policy>"`. When G6 does NOT detect, the LEDGER decision is `not-required-trigger-not-detected` (sentinel). `not-applicable` / `offered-and-declined` are INVALID for REQUIRED-class.
- **OFFERED class** (`design-exploration`, `performance-comparison`, `scope-planning`, `system-framing`, `project-vocabulary`): when G6 detects the trigger, the LEDGER decision MUST be `invoked` / `offered-and-declined: "<user-quoted justification>"` / `required-but-skipped: "<reason>"`. When G6 does NOT detect, the LEDGER decision is `not-applicable`. `not-applicable` is INVALID for OFFERED-class when the matching `trigger-detected-*` line is `yes` (silent-downgrade bypass).

**G6 re-entry on mid-implementation scope change**: when scope materially changes during implementation (e.g., the diff grows beyond the closed-enumeration triviality set after G6 originally said the change was trivial), the agent MUST re-enter G6 per `pre-implementation.md` *G6 re-entry clause* and UPDATE the LEDGER decision lines. The LEDGER reflects the FINAL G6 state, not the initial G6 snapshot. Post-impl rules 12 + 13 catch missed-re-entry cases.

## Investigative workflows (NOT phase playbooks)

Cycle 4 added `cross-file-bug-investigation.md` — a domain-trigger playbook that runs the multi-model panel against **UNCHANGED user-pointed code** for cross-file bug hunting (vs the existing change-implementation pipeline). It's NOT a phase playbook and does NOT add to the POST-CODE-CHANGE LEDGER. Phase enforcement is via the playbook's own orchestrator hard gates at runtime.

| Investigative playbook | Engine | Output | Handoff |
|---|---|---|---|
| `cross-file-bug-investigation.md` + `cross-file-bug-investigation/lanes-catalog.md` | `multi-model-review.md` with `target-type=bug-investigation` (lane-specialized prompts; 7-field finding schema; target-type-specific VERDICT-emission rule) | Citation-verified findings (≤1 rework cap; severity `blocking`/`major`/`minor` + `is_blocking` boolean); per-finding C2 disposition (Step 11A — always) | Optional fix-transition picker (Step 11B — only when intake Q8 ≠ `none`); selected findings persisted to `<session-state>/files/bug-investigation-<ts>.md` (`schema_version: 1`); pre-impl reads via its "Entry points" subsection |
| `codebase-architecture-audit.md` + 5 lens sub-files | single-orchestrator pass over fixed lenses | Ranked debt list with file:line citations | Each picked proposal becomes a normal change through phase playbook chain |
| `least-privilege-audit.md` + 6 axis sub-files | single-orchestrator 6-axis visibility sweep | Per-type matrix with consumer evidence | Picked tightenings become normal changes |

**Discriminator between investigative + audit playbooks** — canonical 6-line block (also in `cross-file-bug-investigation.md` Purpose section; single source of truth):

```
cross-file-bug-investigation = multi-model PANEL with intake-selected LANES on USER-POINTED unchanged code.
codebase-architecture-audit  = single-orchestrator pass over 5 FIXED LENSES for ranked architectural debt.
least-privilege-audit        = 6-AXIS visibility/mutability sweep producing per-type matrix.
code-review (sub-agent)      = single sub-agent reviewing STAGED/UNSTAGED diff (recent changes).
multi-model-review diff      = panel reviewing a DIFF (change).
system-framing               = layered map for ORIENTATION (not bug-hunt).
```

Bare unpaired *"review"* / *"audit"* / *"trace this through the code"* are ambiguous-clarify per AGENTS — these playbooks fire only on artifact-shaped phrases (e.g., cross-file qualifier required for `cross-file-bug-investigation`'s review/audit forms).

## Workflows at a glance

Quick reference for what's in `.github/playbooks/`. Each file is loaded only when its phase fires or its strong-trigger intent is detected and confirmed.

| Playbook | Fires when | Produces |
| --- | --- | --- |
| `pre-implementation.md` | Phase trigger — code edit requested before any implementation | Deepened diagnosis (reproduce → minimise → hypothesise → instrument → reproduction-locked) + G3 approach-selection + G5 safety-critical-skip evaluation + rubber-duck-reviewed plan |
| `post-code-change.md` | Phase trigger — files modified, diff not yet shown | Hygiene cleanup + touched-file LPA + recurring-pattern sweep + §3.1 comment audit gate + `multi-model-review.md` panel + verify-the-fix + builds/tests |
| `pre-commit.md` | Phase trigger — user approved diff | Single-line commit (per `AGENTS.md` §2), no `Co-authored-by` trailer, §4.1 author-identity verify (prompt-when-missing → local config; global opt-in) + commit-ownership prompt with resolved identity + explicit `the agent` / `you (the user)` actor labels |
| `pre-pr-push.md` (INDEX) | Phase trigger — user asks to push, open PR, or request review | §4.2 push-credential verification (mechanism-aware) BEFORE sandbox pre-check + per-commit audit + branch-wide rename-first sweep + branch-wide LPA + state read-back of **10-field predicate** (incl. `pushCredentialsVerified`) before "ready" + separate push-ownership prompt with explicit actor labels |
| `pre-pr-push/per-commit-micro-hygiene.md` | Sub-trigger — per-commit comment audit needed | Audited / amended commit + `perCommitAuditCoverage` entry |
| `pre-pr-push/branch-wide-sweep.md` | Sub-trigger — first push intended for review | Sweep evidence (base SHA + head SHA + base ref) recorded |
| `pre-pr-push/cleanup-commit-buckets.md` | Sub-trigger — sweep produced changes | Default-coarser grouping (file / SUT family / lens / audit category / slice) + 3 cleanup buckets + staging-sprawl guard |
| `pre-pr-push/when-to-re-run-sweep.md` | Sub-trigger — subsequent push on a branch already swept | Re-run decision + copy-forward of prior state |
| `post-pr-review.md` | Phase trigger — PR exists / review comments present | Verified bot finding responses + C2-status-enum per-finding audit + instructions delta |
| `design-spec.md` | Strong trigger — design spec / current-state survey / design-change request / dev design spec | Markdown rendered in chat first; saved to chosen destination only after user approval |
| `ado-task-planning.md` | Strong trigger — ADO task / story / work item drafting | Markdown summary + paste-ready ADO-field block |
| `worktree-setup.md` | Strong trigger — worktree setup / stacked-PR worktree | Hidden-bare + sibling-checkouts layout; `<owner>/<descriptive-name>` branch convention for stacked PRs |
| `software-install.md` | Phase trigger — install / upgrade / uninstall request | Platform-package-manager-first install with vendor-bootstrapper + raw-binary fallbacks |
| `library-restructure.md` | Strong trigger — folder topology restructure / growth planning / de-duplication | VSA topology + clean-arch overlay per §3.12 |
| `least-privilege-audit.md` + `least-privilege-audit/` | Phase trigger (post-code-change touched / pre-pr-push branch-wide) + strong trigger | Per-type matrix across 6 axes with consumer evidence; G6 dead-code default-delete clause in Axis 1 (with exported-API + predicate-field carve-outs) |
| `scope-planning.md` | Strong trigger — light planning before any code | Q&A summary (problem / users / success / scope / constraints) feeding `implementation-planning.md` |
| `project-vocabulary.md` | Strong trigger — per-repo vocabulary doc bootstrap / refresh | Repo-local glossary with stable `### <Term>` headings (NOT always-loaded) |
| `implementation-planning.md` | Strong trigger — deep codebase-aware planning | Implementation plan + decision records + `behaviors_to_cover` (triggers `intent-driven-testing.md` prospective mode) |
| `system-framing.md` | Strong trigger — explain code in context | Layered map (symbol → module → assembly → product surface) + narrative |
| `intent-driven-testing.md` | Phase-sub-step — auto-fires when `behaviors_to_cover` non-empty OR diff has test / SUT delta | Prospective one-test-then-implement loop OR retrospective gap audit; inherits §3.4 checklist |
| `codebase-architecture-audit.md` + `codebase-architecture-audit/` | Strong trigger — read-only audit | Ranked findings list across 5 lenses (§3.7 / §3.8 / §3.10 / §3.11 / §3.12); each picked proposal becomes a normal change through phase playbooks |
| `cross-file-bug-investigation.md` + `cross-file-bug-investigation/` | Strong trigger — panel-driven cross-file bug hunt on UNCHANGED code | Lane-specialized panel report (9 lanes via `multi-model-review.md` target-type `bug-investigation`); citation-verified findings (≤1 rework cap); C2 routing per finding (always) + optional fix-transition picker (when Q8 ≠ none) handing selected findings to `pre-implementation.md` via persisted YAML file (`schema_version: 1`) |
| `design-exploration.md` | Strong trigger — throwaway design prototype | Working variants + decision log; throwaway-hardening (folder + header + build-isolation + 0 production imports + cleanup gate) |
| `performance-comparison.md` | Strong trigger — throwaway benchmark prototype | Variants + benchmark metric + delta + decision log; mandatory `software-install.md` handoff when tooling needs install |
| `multi-model-review.md` + `multi-model-review/` | Strong trigger (panel review) + utility-called by `post-code-change.md` panel hard gate | ≥3 reviewers across model families with mandatory `VERDICT:` per reviewer; 3 convergence models (unanimous / threshold ≥75% / confidence ≥80%); max-loop escalation; C2 status enum for findings dispositions |

Cross-cutting (not playbooks — always-loaded in `AGENTS.md`):

- **Trigger detection** — strong triggers offer the playbook via `ask_user`; weak triggers append a non-blocking offer. Frontmatter + `manifest.yaml` are metadata aids; the router governs detection.
- **Evidence-gate pattern** — structured chat-visible audit output (scope + file:line citations + zero-count justification) required for §3.1 comment audit, cross-cutting findings audit (C2 status enum), pre-PR-push state read-back (carve-out from zero-count — state printed verbatim), post-pr-review per-finding audit, and every new domain playbook's procedure section.
- **Ask-first principle** — every playbook's first executable block is Intake Questions.
- **User-skip policy** — explicit skips warned + recorded; safety-critical skips require re-confirmation. G5 augments the safety-critical set with public-API / folder-restructure / test-migration triggers + ≥3-of-N softer signals.
- **Phase-state tracking** — every phase entry records `phase`, `time_entered`, `intake_status`, `playbook_viewed`, plus per-phase additional fields (e.g. the 10-field pre-PR-push state predicate — incl. `pushCredentialsVerified`).
- **Git identity & push credentials** (`AGENTS.md` §4) — always-loaded. Commit attribution + `git push` authentication MUST belong to the human user, never a disallowed automation identity (case-insensitive match: `Copilot`, `copilot[bot]`, `github-actions[bot]`, `223556219+Copilot@users.noreply.github.com`, other `[bot]` accounts). §4.1: prompt user via `ask_user` when `user.name` / `user.email` missing (local scope by default; global opt-in); author-preservation check on `--amend` / `cherry-pick` / `rebase` / `am`; commit-ownership prompt displays resolved identity + uses explicit `the agent` / `you (the user)` actor labels. §4.2: mechanism-aware push verification (HTTPS+`gh`, system credential helper, SSH, ambient tokens) before EVERY push (incl. sandbox + `gh pr create`); recorded as `pushCredentialsVerified` in pre-PR-push state predicate; push-ownership prompt separate from commit-ownership.
- **Output-write ordering** — documentation playbooks render the draft in chat first.

## Manifest frontmatter, evidence gates, manifest.yaml, multi-model review loop, model registry, sharpened defaults

This repo introduces six cross-cutting patterns layered on top of the existing phase + topic-file architecture. Each is detailed in `.github/playbooks/README.md` *Authoring conventions cross-reference*:

- **Manifest frontmatter** on trigger-fired playbooks (`name` + `description` + optional `triggers`) — metadata only; does NOT drive trigger detection. AGENTS.md semantic discriminator stays canonical.
- **Evidence gates** — structured chat-visible audit output (with scope + citations + zero-count justification) required before declaring a phase / task complete or producing an artifact. Applied to §3.1 comment audit, cross-cutting findings audit, pre-PR-push state read-back, post-pr-review per-finding, and every new domain playbook's procedure.
- **`.github/playbooks/manifest.yaml`** — sibling-of-the-router discoverability index, generated / derived from playbook frontmatter. Consulted only AFTER AGENTS.md router has shortlisted; never drives initial detection. Carries optional `discrimination` prose for ambiguous trigger pairs.
- **Multi-model review loop** (`multi-model-review.md`) — codifies the panel-of-reviewers convergence pattern. Trigger-fired domain + utility-called by `post-code-change.md`'s panel hard gate. Three convergence models; max-loop escalation; C2 status enum for findings dispositions.
- **Model registry decoupling** (`.github/playbooks/multi-model-review/current-model-registry.md`) — capability tier → current model name mapping for multi-model-review panel slots. Playbooks reference abstract tiers (`heavy-claude-xhigh`, `heavy-gpt-premium`, `light-claude`, etc.) instead of literal model names, so model deprecations / renames update in ONE place. Representative current mappings: `heavy-claude-xhigh` = `claude-opus-4.7-xhigh`; `heavy-gpt-premium` = `gpt-5.5`; `light-gpt` = `gpt-5.4-mini`. See the registry for the full 9-tier table + runtime-fallback / substitution rules.
- **Sharpened defaults** — §3.1 stale-comment-disposition (rename-first runs first; then default DELETE) + canonical THROWAWAY: header exception; §3.6 convention precedence (dominant or closest-in-purpose sibling first); pre-implementation G3 (in-scope-only approach-selection) + G5 (safety-critical-skip augmenting User-skip set); cleanup-commit-buckets default coarser grouping; G6 dead-code default-delete folded into LPA Axis 1; worktree-setup stacked-PR discipline.

## Setup (one-time)

### Windows (PowerShell)

```powershell
cd <path-to-this-repo>
.\setup.ps1
```

The script is idempotent: it reads the existing `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` value, asks before overwriting other entries, and backs up `~/.copilot/copilot-instructions.md` (without deleting it) so you can validate the new layout before removing the old monolith.

### Manual setup (Windows)

1. Set the **User-level** environment variable `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` to the absolute path of this cloned repo:
   ```powershell
   [Environment]::SetEnvironmentVariable('COPILOT_CUSTOM_INSTRUCTIONS_DIRS', 'C:\path\to\CopilotInstructions', 'User')
   ```
   Or via System Properties → Advanced → Environment Variables.
2. Restart any open `copilot` terminal sessions (the env var doesn't propagate to running processes).
3. Optional: back up and remove `~/.copilot/copilot-instructions.md` after you've verified the new layout works.

### macOS / Linux

The env var works identically. Run:

```bash
cd <path-to-this-repo>
bash ./setup.sh
```

Or manually add to your shell rc file (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="$HOME/path/to/CopilotInstructions"
```

Then `source` the rc file or open a new terminal. Optional: back up and remove `~/.copilot/copilot-instructions.md` after validating.

### Existing contributors — one-time migration for the catalog-sync hook

If you cloned this repo BEFORE the `.githooks/` directory was introduced, your local clone doesn't have `core.hooksPath` pointed at `.githooks/` and the pre-commit drift safeguard for `HIGH-TIER-SLUGS.md` won't run. Re-run `setup.ps1` (Windows) or `setup.sh` (Unix) — both are idempotent and detect / configure `core.hooksPath` automatically.

Manual migration (any platform):

```sh
git -C <path-to-this-repo> config --local core.hooksPath .githooks
```

CI (`.github/workflows/catalog-sync-check.yml`) is the backstop — even without the local hook, drift is caught at PR-review time. The local hook just gives you faster feedback.

## Verifying the install

> **Context-cost caveat during validation:** if the legacy `~/.copilot/copilot-instructions.md` is still in place, the CLI loads BOTH the legacy monolith AND the new `AGENTS.md` + topic files. This means no actual always-loaded-context reduction yet, and possibly conflicting/duplicate rules in the same session (the docs describe conflict resolution as non-deterministic). Use this validation window to confirm routing only — the context-reduction goal only kicks in after you remove the legacy file in step 3 below.

1. Open a fresh `copilot` session (close all existing ones first — env vars don't propagate to running processes).
2. Inside the session, run the `/instructions` slash command. Confirm:
   - The repo's `AGENTS.md` is listed every session.
   - The matching topic file appears when the working directory contains files of that type. For example, `cd` into a folder with `*.cs` files and `csharp.instructions.md` should be listed.
3. **After successful validation, remove the legacy file** so the context-reduction actually takes effect:
   ```powershell
   Remove-Item "$HOME\.copilot\copilot-instructions.md"
   ```
   The `setup.ps1` backup (`.backup-<timestamp>` in the same folder) lets you restore if anything goes wrong.

## How to add a new topic file

1. Create `.github/instructions/<topic>.instructions.md`.
2. Add YAML frontmatter at the top:
   ```yaml
   ---
   applyTo: "**/*.<ext1>,**/*.<ext2>"
   ---
   ```
   Globs are comma-separated. Optional: `excludeAgent: "code-review"` or `excludeAgent: "cloud-agent"` to exclude an agent type.
3. Write the topic content. Reference back to the core via named refs (e.g., "extends Core / Comments") rather than restating universal rules.
4. Update the `applyTo` table in this README.
5. Commit & push.

## How to add a new playbook

Playbooks live under `.github/playbooks/` and are fetched on demand by the agent — they are NOT auto-loaded by the CLI. Use a playbook when a workflow:

- Has heavy procedural detail that doesn't need to occupy always-loaded context.
- Should run **ask-first** — the agent interviews the user before producing output.
- Is gated by a phase entry or by detection of a strong-trigger intent that the agent confirms via `ask_user`.

To add one:

1. Create `.github/playbooks/<name>.md` (or a sub-folder with an index file if the playbook is large enough to split — see `pre-pr-push/` for the canonical example).
2. Follow the required playbook structure (defined in `.github/playbooks/README.md`):
   - **Purpose** — one paragraph describing what the playbook does and when it fires.
   - **Hard gates** — the bullets that always apply, even if the playbook fetch fails. These should mirror the gates listed in `AGENTS.md` for the corresponding phase.
   - **Intake questions** — the questions the agent must ask via `ask_user` before producing any output. Bundle independent questions; ask sequentially only when a later question depends on the prior answer.
   - **Procedure** — numbered steps the agent runs after intake.
3. Update `AGENTS.md`:
   - Add a row to the workflow router table at the top of §1 mapping the user intent / condition to the new playbook.
   - If the playbook is a new phase: add a phase section with hard gates + STOP directive pointing to the playbook.
   - If the playbook is trigger-fired (design-spec / ADO style): add the trigger phrases to the Trigger detection section.
4. Update the `Layout` tree in this README to show the new playbook.
5. Commit & push.

The CLI picks it up on the next session start (no auto-load registration needed — the agent fetches via `view` when directed).

## Working with this repo

- Edit files in place — the CLI reads the live files in this repo, no sync needed.
- Push to share / back up.
- The slim `AGENTS.md` core stays in scope for every session — workflow phase index, hard gates, universal coding standards (`§3`), commit-message rules (`§2`), and the ask-first / user-skip / state-tracking conventions always apply.
- Topic files only load when their `applyTo` glob matches the working set, keeping context-window usage low for non-matching languages.
- Playbook files only load when the agent reaches the relevant phase or when a strong-trigger intent is detected and the user confirms the offer, keeping heavy procedural detail (multi-model reviewer panels, pre-PR-push comment sweeps, design-spec section lists, ADO field sets) out of always-loaded context.



## Cycle history

The branch `lightweight-gate-v5` was bootstrapped in commit `92f0622` ("Add lightweight-gate-v5: PR Quality Gate system (4/4 panel READY)") and has accumulated 53 commits as of cycle 5 (52 before this maintenance commit), including the original gate build + earlier PR-review pattern-catalog work (PR-558 cycles 1-10). The most recent 4 cycles documented below extend that foundation. Cycle 5 ran the full rubber-duck → 3-reviewer plan panel → unanimous READY → implement → post-impl panel → §0 git safety gates → commit + push workflow; earlier cycles ran similar processes captured in commit history.

| Cycle | Commit      | HIGH slugs | Headline |
|-------|-------------|------------|----------|
| 1     | `12fddeb`   | 24 → 41    | 27 catalog rules + drift safeguard |
| 2     | `577fac9`   | 41 → 43    | 6 rules integrating 4 playbooks at post-impl |
| 3     | `83af4ce`   | 43 → 47    | G6 pre-impl playbook-offer step + 10 rules + 2 post-impl gap-fill |
| 4     | `0ce6d0c`   | 47 → 47    | `cross-file-bug-investigation.md` playbook (NEW investigative use case) |

Per-cycle detail:

- **Cycle 1** (`12fddeb`) — added 27 PR-quality-gate catalog rules + drift safeguard (pre-commit hook + CI workflow + ack mechanism). Established catalog-enforcement-at-commit-time foundation.
- **Cycle 2** (`577fac9`) — added 6 catalog rules integrating 4 in-repo playbooks (LPA, intent-driven-testing, design-exploration, performance-comparison) at POST-IMPLEMENTATION via POST-CODE-CHANGE LEDGER. Playbooks now fire automatically on commit.
- **Cycle 3** (`83af4ce`) — added G6 pre-impl playbook-offer evaluation step + 10 catalog rules covering 7 playbooks at pre-implementation phase + 2 post-impl gap-fill rules. Enforcement extends UPSTREAM to design / implementation phases.
- **Cycle 4** (`0ce6d0c`) — added `cross-file-bug-investigation.md` playbook (9 lanes; new `multi-model-review` target-type `bug-investigation` with target-type-specific 7-field finding schema + VERDICT-emission rule + C2 routing deferred to caller). NEW parallel use case: panel-driven cross-file bug hunting on UNCHANGED code (daily bug-finding work). No new catalog rules.

Rule counts reflect commit-message claims; some commits may net-add fewer than claimed if they also remove rules in the same cycle.

**Maintenance contract**: future cycles append a row to the table + a bullet to the per-cycle detail list in the same commit that introduces the cycle's work; update the bootstrap-paragraph cycle number (cycle 5 → cycle N) + documented-cycle count ("most recent 4 cycles" → "most recent N cycles") + commit count (53 → +M) so the section stays internally consistent.
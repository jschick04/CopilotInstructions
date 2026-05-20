# CopilotInstructions

Personal Copilot CLI custom instructions, split into a slim always-loaded core (`AGENTS.md`), conditionally-loaded topic files (one per language), and **on-demand playbook files** that the agent fetches when entering a workflow phase or when a strong-trigger intent is detected and the user confirms via `ask_user`. Optimized for context-window usage — language-specific style guidance only loads when the working set contains that language, and heavy multi-step procedural detail (post-code-change reviewer panel, pre-PR-push comment sweep, design-spec generation, ADO planning, etc.) only loads when the agent reaches the relevant phase.

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
│       ├── design-exploration.md                       # throwaway prototype (design alternatives / UI variations)
│       ├── performance-comparison.md                   # throwaway benchmark prototype + mandatory software-install.md handoff
│       ├── multi-model-review.md                       # panel-of-reviewers convergence (index) — domain trigger + utility-called by post-code-change
│       ├── multi-model-review/                         # intake / procedure / convergence-models / evidence-gate-spec (incl. C2 status enum)
│       │   ├── intake.md
│       │   ├── procedure.md
│       │   ├── convergence-models.md
│       │   └── evidence-gate-spec.md
│       └── templates/                                  # skeleton / example reference files
│           ├── current-state-survey.md
│           ├── design-change-request.md
│           └── dev-design-spec.md
├── README.md                                           # this file
└── setup.ps1                                           # one-time configuration helper (Windows)
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

## Manifest frontmatter, evidence gates, manifest.yaml, multi-model review loop, sharpened defaults

This repo introduces five cross-cutting patterns layered on top of the existing phase + topic-file architecture. Each is detailed in `.github/playbooks/README.md` *Authoring conventions cross-reference*:

- **Manifest frontmatter** on trigger-fired playbooks (`name` + `description` + optional `triggers`) — metadata only; does NOT drive trigger detection. AGENTS.md semantic discriminator stays canonical.
- **Evidence gates** — structured chat-visible audit output (with scope + citations + zero-count justification) required before declaring a phase / task complete or producing an artifact. Applied to §3.1 comment audit, cross-cutting findings audit, pre-PR-push state read-back, post-pr-review per-finding, and every new domain playbook's procedure.
- **`.github/playbooks/manifest.yaml`** — sibling-of-the-router discoverability index, generated / derived from playbook frontmatter. Consulted only AFTER AGENTS.md router has shortlisted; never drives initial detection. Carries optional `discrimination` prose for ambiguous trigger pairs.
- **Multi-model review loop** (`multi-model-review.md`) — codifies the panel-of-reviewers convergence pattern. Trigger-fired domain + utility-called by `post-code-change.md`'s panel hard gate. Three convergence models; max-loop escalation; C2 status enum for findings dispositions.
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

The env var works identically. Add to your shell rc file (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="$HOME/path/to/CopilotInstructions"
```

Then `source` the rc file or open a new terminal. Optional: back up and remove `~/.copilot/copilot-instructions.md` after validating.

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

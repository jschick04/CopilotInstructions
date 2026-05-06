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
│       ├── README.md                                   # folder convention + required playbook structure (Purpose / Hard gates / Intake / Procedure)
│       ├── pre-implementation.md                       # diagnose + rubber-duck (was AGENTS.md §1 steps 1–2)
│       ├── post-code-change.md                         # multi-model review + verify + tests (was steps 3–6)
│       ├── pre-commit.md                               # diff approval + commit hygiene (was steps 7–8)
│       ├── pre-pr-push.md                              # INDEX — runs intake then dispatches to sub-files (was step 9)
│       ├── pre-pr-push/                                # heaviest playbook split into 4 sub-files
│       │   ├── per-commit-micro-hygiene.md             # per-commit comment audit
│       │   ├── branch-wide-sweep.md                    # branch-wide rename-first sweep
│       │   ├── cleanup-commit-buckets.md               # 3-bucket cleanup commit strategy
│       │   └── when-to-re-run-sweep.md                 # re-run rules after merges / rebases / amends
│       ├── post-pr-review.md                           # pr-review iteration + instructions delta (was step 10)
│       ├── worktree-setup.md                           # was AGENTS.md §9
│       ├── software-install.md                         # was AGENTS.md §10
│       ├── design-spec.md                              # ask-first design-spec generator (current-state survey, design-change request, or dev design spec)
│       ├── ado-task-planning.md                        # ask-first ADO work-item planning generator
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
| `pre-implementation.md` | Phase trigger — code edit requested before any implementation | Verified diagnosis + rubber-duck-reviewed plan |
| `post-code-change.md` | Phase trigger — files modified, diff not yet shown | Multi-model reviewer panel results + verified-the-fix delta + clean build/tests |
| `pre-commit.md` | Phase trigger — user approved diff | Single-line commit (per `AGENTS.md` §2), no `Co-authored-by` trailer |
| `pre-pr-push.md` (INDEX) | Phase trigger — user asks to push, open PR, or request review | Per-commit audit + branch-wide rename-first sweep + bucket-routed cleanup commits + recorded 9-field state predicate (10th informational field for sandbox-confirmation outcome) |
| `pre-pr-push/per-commit-micro-hygiene.md` | Sub-trigger — per-commit comment audit needed | Audited / amended commit + `perCommitAuditCoverage` entry |
| `pre-pr-push/branch-wide-sweep.md` | Sub-trigger — first push intended for review | Sweep evidence (base SHA + head SHA + base ref) recorded |
| `pre-pr-push/cleanup-commit-buckets.md` | Sub-trigger — sweep produced changes | Bucket-1 amend / Bucket-2 single-scope rename amend (with full-repo grep verification) / Bucket-3 separate-commit cross-boundary rename + amend-safety matrix routing |
| `pre-pr-push/when-to-re-run-sweep.md` | Sub-trigger — subsequent push on a branch already swept | Re-run decision + copy-forward of prior 9-field state |
| `post-pr-review.md` | Phase trigger — PR exists / review comments present | Verified-against-source bot finding responses + proposed instructions delta per fix |
| `design-spec.md` | Strong trigger — *"design spec for…"* / *"current-state survey"* / *"design change request"* / *"dev design spec"* / *"implementation spec"* / *"build spec"* / *"architect review"* | One of three modes — Current-State Survey (what's there), Design-Change Request (what should change and why), or Dev Design Spec (how the approved change will be built / deployed / observed / tested) — markdown rendered in chat first; saved to chosen destination only after user approval |
| `ado-task-planning.md` | Strong trigger — *"ADO task / story / work item for…"* / *"acceptance criteria"* / *"definition of done"* / *"draft an ADO …"* | Two paired outputs — structured markdown summary + paste-ready ADO-field block (Title / Description / AC / DoD / Tags + per-type extras for Bug / Story / Task / Feature / Epic) |
| `worktree-setup.md` | Strong trigger — *"set up worktree"* / *"hidden bare repo layout"* | Hidden-bare + sibling-checkouts layout per `AGENTS.md` §9 |
| `software-install.md` | Phase trigger — install / upgrade / uninstall request | Platform-package-manager-first install (winget / brew / apt / dnf / pacman) with vendor-bootstrapper fallback (signature + magic-bytes + embedded-version-metadata gate) and raw single-file binary fallback (provenance + signed checksum + magic bytes + post-install `--version` cross-check) |

Cross-cutting (not playbooks — always-loaded in `AGENTS.md`):

- **Trigger detection** (strong vs weak) — strong triggers offer the playbook via `ask_user`; weak triggers append a non-blocking sentence offering it.
- **Ask-first principle** — every playbook's first executable block is an Intake Questions section; the agent runs intake before producing any output.
- **User-skip policy** — explicit skips are warned, recorded in canonical session todos, and enumerated in any "ready to commit / push" message; safety-critical skips require re-confirmation.
- **Phase-state tracking convention** — every phase entry records `phase`, `time_entered`, `intake_status`, `playbook_viewed`, plus per-phase additional fields (e.g. the 9-field pre-PR-push state predicate plus the informational `sandboxPriorExposureConfirmation`).
- **Output-write ordering** — documentation playbooks render the draft in chat first, save to destination only after user approval.

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

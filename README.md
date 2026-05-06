# CopilotInstructions

Personal Copilot CLI custom instructions, split into a slim always-loaded core (`AGENTS.md`) plus topic files that conditionally load via `applyTo:` globs. Optimized for context-window usage — language-specific style guidance only loads when the working set actually contains that language.

## Layout

```
CopilotInstructions/
├── AGENTS.md                                           # always loaded — workflow, comments, naming, tests, perf, defaults, state predicates, smells, worktree, install
├── .github/
│   └── instructions/
│       ├── csharp.instructions.md                      # C# / Razor / .NET
│       ├── cpp.instructions.md                         # C / C++
│       ├── javascript-typescript.instructions.md       # JS / TS
│       ├── html.instructions.md                        # HTML / Razor / cshtml markup
│       └── css.instructions.md                         # CSS / SCSS / SASS / LESS
├── README.md                                           # this file
└── setup.ps1                                           # one-time configuration helper (Windows)
```

## How loading works

The Copilot CLI loads custom instructions from several documented locations. This repo uses the `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` environment variable, which is a **comma-separated** list of directories. For each listed directory the CLI looks for:

- `AGENTS.md` (loaded as additional always-on instructions for every session)
- `.github/instructions/**/*.instructions.md` (each file is conditionally loaded based on the `applyTo:` glob in its YAML frontmatter)

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

## Working with this repo

- Edit files in place — the CLI reads the live files in this repo, no sync needed.
- Push to share / back up.
- The slim `AGENTS.md` core stays in scope for every session, so workflow rules (rubber-duck, code-review, multi-model agreement, commit hygiene, etc.) always apply.
- Topic files only load when their `applyTo` glob matches the working set, keeping context-window usage low for non-matching languages.

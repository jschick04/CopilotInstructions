# Lens: project layout (§3.11)

## Purpose

Apply AGENTS.md §3.11 (project and library structure) to in-scope code. Checks whether the repo follows the blessed ecosystem layout (e.g., `src/` + `tests/`, lockfile placement, build-config placement) and surfaces cost-bearing deviations. Sub-file of `codebase-architecture-audit.md`.

## Hard gates

- **Read-only**.
- **Per-lens evidence-gate output** before findings (see *Procedure* step 4).
- **Source-grounded**: every finding cites the file / folder path AND the ecosystem-standard reference point being deviated from.
- **Deviation must have cost**: surface only deviations that have a real cost (broken test discovery, hand-maintained CI working-directory flags, lockfile duplication, build-config below the projects it governs). Stylistic-only deviations are out-of-scope for this lens.

## Inherits

Scope, risk-tolerance, and output destination from the calling index.

## Procedure

1. **Detect ecosystem** - read manifest files: `*.csproj` / `*.sln` / `*.slnx` → .NET; `package.json` / `tsconfig.json` → Node/TS; `pyproject.toml` / `setup.py` → Python; `Cargo.toml` → Rust; `go.mod` → Go; `pom.xml` / `build.gradle` → Java/Kotlin. Multi-ecosystem repos: apply each table row independently to the matching subtree.
2. **Compare against blessed layout** - apply the AGENTS.md §3.11 ecosystem-layout table (single source of truth). For each detected ecosystem, read the §3.11 row and check the repo against (a) the production-code path, (b) the tests path, and (c) the root-level config files for that ecosystem. Do not re-enumerate the table here.
3. **Cost classification** - for each deviation, identify the actual cost:
   - Test discovery broken / hand-listed in CI?
   - Pipeline `cd` / `--working-directory` workarounds?
   - Lockfile duplication across nested subdirectories?
   - Build-config (`Directory.Build.props`, `pyproject.toml`, `tsconfig.json`, `Cargo.toml`) sitting BELOW the projects it should govern?
   - Integration tests living next to unit tests with no separation when > 2 test projects?
   - Production code intermixed with tests in the same root folder?
   If no cost, the deviation is stylistic - do not flag.
4. **Per-lens evidence-gate output**:

   ```
   Lens project-layout audit: scope=<ecosystems detected, manifests read>, E ecosystems, F findings.
   - by ecosystem: <ecosystem>: N deviations with cost - <path + standard-deviation pair>
   - cost-bearing deviation: <kind>: <count>
   - zero-count justification when 0 (e.g., ".NET: 0 - src/ + tests/ layout intact, build-config at root, no nested lockfiles")
   ```

5. **Findings list** - severity (typically major when CI / build is hand-worked-around, minor when stylistic-with-cost), location, issue, proposal (restructure path / move config / split tests). **Intent-clarity justification** for layout findings frequently cites *"contributor-onboarding cost - new contributors learn standard layout once; project-specific shape costs every new contributor"*.

## Output

Findings list + per-lens evidence-gate audit. Consumed by `codebase-architecture-audit.md` aggregation step.

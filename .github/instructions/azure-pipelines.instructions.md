---
applyTo: "azure-pipelines*.yml,azure-pipelines*.yaml,**/.azdo/**/*.yml,**/.azdo/**/*.yaml,**/.azuredevops/**/*.yml,**/.azuredevops/**/*.yaml"
---

# Azure DevOps Pipelines (YAML) Instructions

<!-- read-receipt-token: 4deeb0f2 -->

> **Topic instruction file - not the whole ruleset.** The mandatory governed workflow (`AGENTS.md` §0 git-safety gates + §1 pre-implementation / post-code-change phase gates + the playbook router incl. `multi-model-review`) lives at the instruction-set repo root. If `AGENTS.md` is not already in your context this session, read it before editing.

> **Scope:** loaded on Azure DevOps YAML pipelines (`azure-pipelines*.yml`, `.azdo/`, `.azuredevops/`). NOT GitHub Actions - those live under `.github/workflows/` and are out of this glob. Industry-standard ADO pipeline standards + recurring smells to audit during self-review and panel review - extend with project-specific conventions as they emerge. Advisory lens; no mechanical gate verifies these.

---
## Azure Pipelines standards
- Type variables via variable groups; name every stage and job; give each step a `displayName`.
- Secrets are never echoed (use `issecret=true` on `task.setvariable`; keep secrets out of `Write-Host` / `echo`).
- Pin task major versions and the agent image; keep `trigger` / `pr` scoping intentional.

## Azure Pipelines recurring smells
- **Inline secret / PAT / token literals instead of a variable group / Key Vault-linked group / secret variable.** Secrets in YAML land in source control and logs. Grep for token / PAT / connection-string-shaped literals; route them through a secret variable or a Key Vault-linked variable group.
- **Task version floating or unpinned (`Task@*`) vs a pinned major.** A floating task version silently changes behavior between runs. Confirm each `- task:` pins a major version (e.g. `@2`).
- **Missing or implicit `dependsOn` causing wrong stage / job order.** Without explicit `dependsOn`, stages may run in an unintended order or in parallel. Audit multi-stage / multi-job pipelines for the intended ordering.
- **`latest` or unpinned agent `vmImage`.** `vmImage: 'ubuntu-latest'` drifts as the hosted image rolls forward. Prefer a pinned image label where reproducibility matters.
- **`${{ }}` template-expression interpolation of untrusted input (script injection).** Interpolating PR titles / branch names / external input directly into a `script:` body lets an attacker inject shell commands. Pass untrusted values via environment variables and reference them as `$(VAR)` inside the script, not via `${{ }}` string splicing.
- **`condition:` referencing a misspelled or undefined variable (silently false).** A typo in a `condition:` expression evaluates to false and silently skips a step / stage with no error. Spot-check condition variable names against where they are defined.
- **`checkout` / `persistCredentials` defaults that over-expose the token.** `persistCredentials: true` leaves the build token on disk for later steps; default checkout grants broad scope. Confirm the token exposure matches what the steps actually need.
- **Trigger / PR scoping too broad.** A `trigger:` / `pr:` that fires on every branch / path runs the pipeline more than intended. Scope `branches` / `paths` to what the pipeline is meant to validate.

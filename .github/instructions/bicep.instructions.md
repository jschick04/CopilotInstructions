---
applyTo: "**/*.bicep"
---

# Bicep Infrastructure-as-Code Instructions

<!-- read-receipt-token: 8240760e -->

> **Scope:** loaded on `.bicep` files. Industry-standard Bicep standards + recurring smells to audit during self-review and panel review - extend with project-specific conventions as they emerge. Advisory lens; no mechanical gate verifies these.

---
## Bicep standards
- Declare parameters at the top with `@description`; constrain with `@allowed` / `@minLength` / `@maxLength` where applicable.
- Factor repeated resources into modules; keep each module focused on one concern.
- Outputs never expose secrets (no secret / key / connection-string outputs).
- Prefer `resourceGroup().location` (or a `location` param defaulted to it) over a hardcoded region.

## Bicep recurring smells
- **Secret / connection-string literals instead of `@secure()` params or Key Vault references.** Hardcoded secrets land in source control and deployment logs. Grep for connection-string / key-shaped literals; route them through `@secure()` parameters or `getSecret` / Key Vault references.
- **`@secure()` missing on a password / secret parameter.** A secret-bearing param without `@secure()` is logged in deployment output. Audit every param whose name implies a secret (`password`, `secret`, `key`, `token`, `connectionString`) for the decorator.
- **A secret echoed in an `output`.** `output` values are persisted in deployment history and readable by anyone with deployment read access. Spot any output sourced from a secure param or a `listKeys` / `listSecrets` call.
- **Hardcoded `location` instead of a param or `resourceGroup().location`.** A pinned region blocks redeploying the template elsewhere. Spot `location: 'eastus'`-style literals.
- **Unpinned or stale resource `apiVersion`.** Omitting or floating `apiVersion` (or carrying a years-old one) yields nondeterministic / deprecated behavior. Confirm each resource pins a current `apiVersion`.
- **Implicit-only dependencies where an explicit `dependsOn` is needed.** Relying on inferred ordering when a resource needs another fully provisioned first causes flaky deploys. Spot resources that reference outputs of a sibling but lack the needed ordering.
- **Resource names not parameterized or not uniqued.** Hardcoded global names (storage, key vault) collide across environments. Prefer `uniqueString(resourceGroup().id)` or a name param.
- **Overly broad role assignments.** Granting `Owner` / `Contributor` at subscription / resource-group scope where a narrower built-in role + resource scope suffices. Audit `roleDefinitionId` + scope for least privilege.

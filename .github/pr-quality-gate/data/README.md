# PR Quality Gate — Findings Data

Global, project-deidentified telemetry. One CSV file shared across all CopilotInstructions consumers, written via file-locked append.

## Schema (`findings.csv`)

```
timestamp,revision,pattern_slug,classification,finding_brief,slate_mode,finding_type
```

| column | type | description |
|---|---|---|
| `timestamp` | ISO-8601 UTC (`2026-05-24T22:30:00Z`) | When the finding was recorded; no timezone or fractional-second variation |
| `revision` | 40-char SHA | Catalog SHA for `finding_type=pattern`, prefs SHA for `finding_type=preference` |
| `pattern_slug` | text | From `pattern-catalog.md` or `coding-preferences.md` |
| `classification` | enum `real \| false-positive \| recurring-false-positive \| dismissed-out-of-scope \| routed-deferred \| pending` | Classification at write time; initial = `pending`, post-resolution = updated by maintenance protocol |
| `finding_brief` | text (CSV-escaped) | Generic 1-line description; NO project-identifying tokens (no file paths, no commit SHAs, no PR numbers, no branch names, no usernames) |
| `slate_mode` | enum `full \| triage \| lint-only` | Mode the gate ran in; required for trend stratification |
| `finding_type` | enum `pattern \| preference` | Source of the finding (catalog pattern vs coding preference) |

## Project agnosticism (load-bearing invariant)

This CSV MUST NOT contain:
- Repository URLs
- Project names or `project_hash`
- File paths
- Branch names
- Commit SHAs (for the consuming project — `revision` is CopilotInstructions SHA only)
- PR numbers
- Usernames or developer identities
- Any free-text that could deanonymize the consuming project

`finding_brief` uses generic phrasings (e.g., `"async-correctness hit"`, `"XML doc mismatch on volatile field"`, `"empty-array index access"`). Per-PR specifics live in the ephemeral QUALITY GATE block in the agent's session, not in this persistent CSV.

The CSV lives in the CopilotInstructions repo. Per the §1B carve-out (see `../README.md` §"findings.csv schema"), this is acceptable BECAUSE the data is anonymized — the lock-file design + project-agnostic schema together guarantee no project leakage at rest.

## File locking semantics

Lock file: `findings.csv.lock` (this directory). JSON content:

```json
{
  "pid": 12345,
  "host": "hostname",
  "session_id": "uuid-or-pid-timestamp",
  "acquired_at": "2026-05-24T22:30:00Z"
}
```

Acquisition (atomic-creation via `CreateNew` in PowerShell / `(set -C; ...) 2>/dev/null` in bash):
- Default timeout: **30 seconds** (configurable via `-LockTimeoutSeconds`)
- Jittered exponential backoff: 50-250ms initial, doubles on retry, capped at 5 seconds
- On timeout: exit 4 with `Could not acquire findings.csv lock within Ns`

Stale lock detection:
- Lock age > 5 minutes AND owner pid is dead on owner host → break the lock (emit `[gate-runner] Stale lock from pid N; breaking` to stderr)
- Locks from a DIFFERENT host always treated as live — gate-runner does not probe remote processes
- For CI-runner ephemeral VMs that may leave permanent locks: operators should run a manual cleanup pass via `find . -name '.lock' -mmin +120 -delete` on the data directory (out of scope for gate-runner itself)

On crash:
- Lock file persists; next session sees stale lock + applies the heuristic
- Always-clean shutdown removes the lock in a `finally`/`trap` block

## Adding rows

Rows are appended ONLY by `gate-runner.ps1` / `gate-runner.sh` after a successful gate run. The catalog maintenance protocol (in `../pattern-catalog.md`) updates `classification` retrospectively after a PR converges or merges — those updates also go through the file lock.

Manual `findings.csv` edits are discouraged. If absolutely necessary, ensure no project-identifying tokens leak in.

## Trend queries

Run with `sqlite3` (using CSV import) or `Import-Csv` in PowerShell:

```sql
-- Pattern frequency over last N days
SELECT pattern_slug, COUNT(*) AS hits FROM findings WHERE timestamp > '<cutoff>' GROUP BY pattern_slug ORDER BY hits DESC;

-- FP rate by pattern
SELECT pattern_slug,
       SUM(CASE WHEN classification IN ('false-positive','recurring-false-positive') THEN 1 ELSE 0 END) AS fp,
       COUNT(*) AS total
  FROM findings GROUP BY pattern_slug ORDER BY fp DESC;

-- Mode stratification (don't aggregate across modes — recall rates differ structurally)
SELECT pattern_slug, slate_mode, COUNT(*) AS hits FROM findings GROUP BY pattern_slug, slate_mode;
```

Aggregate trends only — without `project_hash`, per-project recurrence cannot be computed from this CSV alone (acknowledged trade-off; per-project signal lives in the agent's session memory + `plan.md`).

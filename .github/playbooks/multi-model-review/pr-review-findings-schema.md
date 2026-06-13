# PR-review-findings schema

Schema for per-project SQL telemetry of GitHub Copilot PR review findings + agent classifications. Persisted at `<project-root>/.github/data/pr-review-findings.csv` (or `.sqlite` for projects preferring structured storage). The schema is project-deidentified at the column-name level; project-specific data (file paths, project slug) lives in row values.

## Storage location decision

| Storage | Cross-session | Multi-project | Notes |
|---|---|---|---|
| Project repo `.github/data/pr-review-findings.csv` | Yes (in repo) | One file per project | **Recommended** - keeps project data with the project; shared via git |
| CopilotInstructions repo | Yes | Mixed (column-keyed) | Rejected - per-project data has no place in the shared instruction repo per §1B project-agnosticism |
| Session-store DuckDB | No (per-session) | No | Useful for in-session analytics but does NOT persist across PR rounds without explicit export |
| In-memory / chat-only | No | No | Lost on context compaction |

Each consuming project owns its own findings file. The catalog maintenance protocol (in `pr-review-pattern-catalog.md`) reads/writes the consuming project's file, never CopilotInstructions.

## Columns

| Column | Type | Description | Required |
|---|---|---|---|
| `id` | integer | Surrogate primary key | yes |
| `pr_number` | integer | The PR number on the upstream repo (`github.com/<org>/<repo>/pull/<N>`) | yes |
| `round` | integer | Which review round within the PR (1-indexed; matches `fixIterationCount` from `pre-pr-creation-review.md` Step 6) | yes |
| `review_timestamp` | TEXT (ISO 8601) | When Copilot posted the review comment | yes |
| `file_path` | TEXT | Repo-relative path. Per-project storage means no project-key column is required; the file's location identifies the consuming project | yes |
| `line_number` | INTEGER | Line referenced in the finding | optional (no line for PR-description findings) |
| `category` | TEXT | The §2D 11-category number (e.g., "Cat 4") OR pattern slug from `pr-review-pattern-catalog.md` (e.g., "async-correctness") | yes |
| `finding_summary` | TEXT | One-sentence summary of the finding | yes |
| `classification` | TEXT enum: `real` / `false-positive` / `recurring-false-positive` / `dismissed-out-of-scope` / `routed-deferred` | The agent's classification | yes |
| `fix_commit` | TEXT (short SHA) | If `classification=real`, the commit SHA that resolved the finding | optional (NULL until fix lands) |
| `dismissal_rationale` | TEXT | If `classification` is a FP / dismissed / deferred variant, the source-grounded rationale | optional (required for FP/dismissed) |
| `pattern_slug` | TEXT | Slug from `pr-review-pattern-catalog.md` (e.g., `aria-binding`); links the finding to a catalog pattern entry | optional |
| `fp_registry_id` | TEXT | If `classification=recurring-false-positive`, the FP-N id from `known-false-positives.md` | optional |
| `created_at` | TEXT (ISO 8601) | When the row was inserted | yes |

## CSV file format

Plain CSV with header row. Encoding: UTF-8 with BOM (so Excel opens cleanly). Newlines: LF or CRLF (whichever the consuming project uses). Quoting: standard CSV (double-quotes around fields containing commas, newlines, or quotes; escape quotes as `""`).

Example header + first data row:

```
id,pr_number,round,review_timestamp,file_path,line_number,category,finding_summary,classification,fix_commit,dismissal_rationale,pattern_slug,fp_registry_id,created_at
1,123,11,2026-05-24T17:12:32Z,src/SampleProject.UI/Views/SomeViewBase.cs,130,Cat 1,"OnPinStateChanged early-return logic inversion",real,abc1234d,,logic-inversion,,2026-05-24T17:15:00Z
```

(Example uses placeholder paths - the consuming project's file would have its own real paths.)

## SQLite alternative

For projects with high finding volume (>500 rows), a SQLite file at `<project-root>/.github/data/pr-review-findings.sqlite` is preferred. Schema:

```sql
CREATE TABLE pr_review_findings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pr_number INTEGER NOT NULL,
    round INTEGER NOT NULL,
    review_timestamp TEXT NOT NULL,
    file_path TEXT NOT NULL,
    line_number INTEGER,
    category TEXT NOT NULL,
    finding_summary TEXT NOT NULL,
    classification TEXT CHECK (classification IN ('real', 'false-positive', 'recurring-false-positive', 'dismissed-out-of-scope', 'routed-deferred')) NOT NULL,
    fix_commit TEXT,
    dismissal_rationale TEXT,
    pattern_slug TEXT,
    fp_registry_id TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_pr_round ON pr_review_findings(pr_number, round);
CREATE INDEX idx_classification ON pr_review_findings(classification);
CREATE INDEX idx_pattern_slug ON pr_review_findings(pattern_slug);
```

The same DDL is reproduced in this file so the agent can re-create the table from scratch in any new consuming project.

## Trend queries

These are illustrative queries the catalog maintenance protocol (`pr-review-pattern-catalog.md`) can use to re-classify patterns. Run with `sqlite3` on the per-project file (no `project` predicate needed - single-project file):

```sql
-- Pattern frequency over last N PRs (drives high/low-frequency promotion/demotion)
SELECT pattern_slug, COUNT(*) AS hits, COUNT(DISTINCT pr_number) AS prs
FROM pr_review_findings
WHERE classification = 'real' AND pr_number > <threshold-pr-number>
GROUP BY pattern_slug
ORDER BY hits DESC;

-- FP rate trajectory (are we dismissing fewer over time?)
SELECT pr_number,
    SUM(CASE WHEN classification = 'real' THEN 1 ELSE 0 END) AS real_count,
    SUM(CASE WHEN classification IN ('false-positive', 'recurring-false-positive') THEN 1 ELSE 0 END) AS fp_count
FROM pr_review_findings
GROUP BY pr_number
ORDER BY pr_number DESC;

-- Recurring FPs (drives FP-N entry priority + mitigation candidate evaluation)
SELECT fp_registry_id, COUNT(*) AS hits, COUNT(DISTINCT pr_number) AS prs
FROM pr_review_findings
WHERE classification = 'recurring-false-positive'
GROUP BY fp_registry_id
ORDER BY hits DESC;

-- Patterns with decaying hit rate (candidates for demotion from high-frequency battery)
WITH recent AS (SELECT pattern_slug, COUNT(*) AS hits_recent FROM pr_review_findings WHERE pr_number > <recent-threshold> GROUP BY pattern_slug),
     prior AS (SELECT pattern_slug, COUNT(*) AS hits_prior FROM pr_review_findings WHERE pr_number BETWEEN <older-threshold> AND <recent-threshold> GROUP BY pattern_slug)
SELECT COALESCE(r.pattern_slug, p.pattern_slug) AS pattern_slug,
    COALESCE(r.hits_recent, 0) AS recent, COALESCE(p.hits_prior, 0) AS prior
FROM recent r FULL OUTER JOIN prior p ON r.pattern_slug = p.pattern_slug
WHERE COALESCE(r.hits_recent, 0) < COALESCE(p.hits_prior, 0)
ORDER BY (COALESCE(p.hits_prior, 0) - COALESCE(r.hits_recent, 0)) DESC;
```

## Initial seeding

For a project new to this telemetry system, the bootstrap procedure is:

1. Create `<project-root>/.github/data/pr-review-findings.csv` with header row only.
2. Walk the project's last 10-20 PRs via `gh api repos/<owner>/<repo>/pulls/<N>/comments --paginate --jq '.[] | select(.user.login == "Copilot")'`.
3. For each comment: classify (regex first-pass; manual review for unclassified); insert row.
4. Run trend queries to identify the project's high-frequency patterns; propose catalog updates (CopilotInstructions PR) if any project-specific pattern recurs ≥3 times.

This file is owned by the agent + reviewed in PRs like any other code artifact. Schema changes here are §1B instruction-repo edits and require panel certification.

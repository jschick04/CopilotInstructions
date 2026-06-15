parent_sha: fbef7e205a78db483853fef7e21e336adf9bc570
commit_subject: Fix leakage-regex bot-substring false-positive; bump model registry
POST-CODE-CHANGE LEDGER
  files-touched: 6 (rename-blind, audits/** excluded: 00-catalog source + regenerated pattern-catalog + regenerated HIGH-TIER-SLUGS + pre-commit.md recipe + current-model-registry.md + README.md representative-mapping)
  profile: full
  gates:
    hygiene-cleanup: ran
    touched-file-LPA: N/A: no visibility/export surface delta
    vsa-audit: ran (governance/catalog edit; no new layout)
    emdash-scan: ran, clean
    recurring-pattern-sweep: ran, 0 findings
    prior-PR-review-sweep: ran, 0 findings
    dry-audit: ran, 0 duplication
    post-code-change-panel: ran, unanimous
    intent-driven-testing-audit: ran: regex behavior verified (false-positives like both/robot no longer trip; genuine panel-artifact phrases still trip); catalog regen verified; leakage-scan recipe ported to portable pwsh Select-String with precise +++ header-skip (13 adversarial diff-line cases)
    comment-audit-3.1: ran, 0 new comment sites
    build: N/A: no compile step (markdown + catalog regen)
    tests: passed, verify-pattern-catalog + smart-punctuation + leakage-regex behavior all green
    diff-shown: yes
    commit-message-approved: pending

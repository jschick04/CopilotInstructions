parent_sha: 72cd8a6da7563ebece5947a0a9e4449ad31a4342
commit_subject: Add post-code-change panel-ledger gate and dedup profile templates
POST-CODE-CHANGE LEDGER
  files-touched: 21 (rename-blind, audits/** receipts excluded: 4 profile-rename paths + 4 new scripts + 13 modified)
  profile: full
  gates:
    hygiene-cleanup: ran
    touched-file-LPA: N/A: no visibility/export surface delta
    vsa-audit: ran (new files under scripts/, scripts/lib/, scripts/tests/ - consistent with existing layout)
    emdash-scan: ran, clean
    recurring-pattern-sweep: ran, 0 findings
    prior-PR-review-sweep: ran, 0 findings
    dry-audit: ran, 1 duplication (Invoke-Git ~15 lines), 1 waived (isolation-over-DRY, panel-endorsed)
    post-code-change-panel: ran, unanimous
    intent-driven-testing-audit: ran: 65 panel-ledger self-tests + 78 comment-audit self-tests (incl new bootstrap-hardening cases)
    comment-audit-3.1: ran, 17 sites covered
    build: N/A: no compile step (PowerShell + markdown + shell)
    tests: passed, 143/143 (comment-audit 78 + panel-ledger 65)
    diff-shown: yes
    commit-message-approved: yes

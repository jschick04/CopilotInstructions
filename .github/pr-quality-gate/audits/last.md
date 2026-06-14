parent_sha: 46555b06ad7df1b992ef10356b12d0f11a26198b
commit_subject: Harden CI script repo-root resolution against directory false-pass
Comment audit: scope=new repo-root resolver lib + tests + 12-script adoption + workflow/README wiring (rebased onto main after PR #6 merge), 5 new comment site(s), all covered (2 lib contract-header + 2 test-header + 1 SHA-pin annotation).
- .github/workflows/pr-gate-check.yml:89: approval_turn: user 'full-robust' + rebase-and-repanel (impl-panel-converged 4/4) | allowed-case: external constraint | justification: SHA-pin v4 annotation on the checkout action for the new repo-root-tests job
- scripts/lib/repo-root.psm1:1: approval_turn: user 'full-robust' + rebase-and-repanel (impl-panel-converged 4/4) | allowed-case: non-obvious invariant | justification: file contract header - repo-root resolver precedence (candidate-validate-fall-through) + fail-closed contract
- scripts/lib/repo-root.psm1:24: approval_turn: user 'full-robust' + rebase-and-repanel (impl-panel-converged 4/4) | allowed-case: non-obvious invariant | justification: contract header close - worktree-safe git -C is-inside-work-tree note
- scripts/tests/repo-root.tests.ps1:2: approval_turn: user 'full-robust' + rebase-and-repanel (impl-panel-converged 4/4) | allowed-case: trade-off | justification: standalone pwsh self-test header for the resolver
- scripts/tests/repo-root.tests.ps1:3: approval_turn: user 'full-robust' + rebase-and-repanel (impl-panel-converged 4/4) | allowed-case: trade-off | justification: run command

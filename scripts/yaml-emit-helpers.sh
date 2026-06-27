#!/usr/bin/env bash
# YAML single-quote scalar helper -- bash twin of scripts/lib/yaml-emit-helpers.psm1 with byte-identical output (see it for rationale).
# Renders a free-text value (pr_ref, prior_slugs) as a single-line scalar so it cannot reshape gate-runner.sh's
# contract block. Parity pinned by scripts/tests/yaml-emit-helpers.tests.ps1.
yaml_sq() {
    # Pattern spans 0x01-0x1F + DEL: NUL cannot occur in a bash variable and is unreachable in CSV input (the pwsh
    # twin spans 0x00 too, so both agree on every reachable value).
    local LC_ALL=C
    local v=${1//[$'\001'-$'\037'$'\177']/ }
    v=${v//\'/\'\'}
    printf "'%s'" "$v"
}

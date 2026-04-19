#!/usr/bin/env bats
# test/01-build.bats — verify build script CLI option coverage.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    BUILD="${REPO_ROOT}/build"
    STAGING="${REPO_ROOT}/test/staging"
}

@test "build --help lists --advice option" {
    run "${BUILD}" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--advice"* ]]
}

@test "build --help lists --cache option" {
    run "${BUILD}" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--cache CACHE_RULES"* ]]
}

@test "build --advice scout enables Scout advisement stage" {
    run "${BUILD}" --advice scout --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stage 5b: Advise (Scout)"* ]]
}

@test "build --advise DIVE enables Dive advisement stage" {
    run "${BUILD}" --advise DIVE --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stage 5c: Advise (Dive)"* ]]
}

@test "build --advise Dive enables Dive advisement stage" {
    run "${BUILD}" --advise Dive --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stage 5c: Advise (Dive)"* ]]
}

@test "build --advise none disables all advisements" {
    run "${BUILD}" --advise none --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "$output" != *"Stage 5a"* ]]
    [[ "$output" != *"Stage 5b"* ]]
    [[ "$output" != *"Stage 5c"* ]]
}

@test "build --advise NONE disables all advisements" {
    run "${BUILD}" --advise NONE --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "$output" != *"Stage 5a"* ]]
    [[ "$output" != *"Stage 5b"* ]]
    [[ "$output" != *"Stage 5c"* ]]
}

@test "build --advice none disables all advisements" {
    run "${BUILD}" --advice none --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "$output" != *"Stage 5a"* ]]
    [[ "$output" != *"Stage 5b"* ]]
    [[ "$output" != *"Stage 5c"* ]]
}

@test "build --no-advise disables all advisements" {
    run "${BUILD}" --no-advise --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "$output" != *"Stage 5a"* ]]
    [[ "$output" != *"Stage 5b"* ]]
    [[ "$output" != *"Stage 5c"* ]]
}

@test "build --advise scout,dive enables Scout and Dive" {
    run "${BUILD}" --advise scout,dive --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stage 5b: Advise (Scout)"* ]]
    [[ "$output" == *"Stage 5c: Advise (Dive)"* ]]
}

@test "build --advise rejects unknown advisement" {
    run "${BUILD}" --advise unknown --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown advisement"* ]]
}

@test "build defaults to no advisory scans" {
    run "${BUILD}" --dry-run --no-lint --no-test --no-scan
    [ "$status" -eq 0 ]
    [[ "$output" != *"Stage 5a"* ]]
    [[ "$output" != *"Stage 5b"* ]]
    [[ "$output" != *"Stage 5c"* ]]
}

@test "build --cache reset=all resets Trivy DB" {
    run "${BUILD}" --cache "reset=all" --dry-run --no-lint --no-test --no-scan --no-advise
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cache: reset Trivy DB"* ]]
}

@test "build --cache reset=all resets Grype DB" {
    run "${BUILD}" --cache "reset=all" --dry-run --no-lint --no-test --no-scan --no-advise
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cache: reset Grype DB"* ]]
}

@test "build --cache Reset=All resets both caches" {
    run "${BUILD}" --cache "Reset=All" --dry-run --no-lint --no-test --no-scan --no-advise
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cache: reset Trivy DB"* ]]
    [[ "$output" == *"Cache: reset Grype DB"* ]]
}

@test "build --cache Skip-Update=TrIvY skips Trivy DB update" {
    run "${BUILD}" --cache "Skip-Update=TrIvY" --dry-run --no-lint --no-test --no-scan --no-advise
    [ "$status" -eq 0 ]
    [[ "$output" == *"Trivy DB update skipped"* ]]
}

@test "test/staging --help lists --scan option" {
    run "${STAGING}" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--scan"* ]]
}

@test "test/staging --help lists --advise option" {
    run "${STAGING}" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--advise"* ]]
}

@test "test/staging --help lists --cache option" {
    run "${STAGING}" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--cache CACHE_RULES"* ]]
}

@test "test/staging --cache requires an argument" {
    run "${STAGING}" --cache
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "test/staging --cache reset=all accepted without error" {
    run "${STAGING}" --cache "reset=all" --no-scan --no-advise --image nonexistent-image-$(date +%s) 2>&1 || true
    [[ "$output" != *"Unknown --cache rule"* ]]
    [[ "$output" != *"Unknown cache target"* ]]
}

@test "test/staging --cache rejects unknown rule key" {
    run "${STAGING}" --cache "bad-key=trivy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown --cache rule key"* ]]
}

@test "test/staging --cache rejects unknown target" {
    run "${STAGING}" --cache "reset=badtarget"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown cache target"* ]]
}

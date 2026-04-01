#!/usr/bin/env bats
# test/10-pfsense-backup-cli-flags.bats — extended CLI flag coverage for src/pfsense-backup.
#
# Covers: --build-date, --git-commit, missing-argument guards, --user,
# --strict-host-key-checking no, --compression and --gpg-passphrase as CLI
# flags, -b/--bucket CLI flag, password-file CLI flag, and stdout mode output.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    WHEREAMI="${BATS_TEST_DIRNAME}"
    IMAGE="${IMAGE:-1121citrus/pfsense-backup:latest}"
    chmod +x "${WHEREAMI}/bin/"*
    export WHEREAMI IMAGE

    # Run pfsense-backup writing to stdout only; extra docker flags via "$@".
    # Stderr is discarded — use only for exit-status and stdout assertions.
    # shellcheck disable=SC2317
    run_pfsense_backup() {
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -e PFSENSE_HOST=fake-host \
            -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
            -e PFSENSE_IDENTITY_PASSWORD=testpassword \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
            "$@" \
            "${IMAGE}" /usr/local/bin/pfsense-backup 2>/dev/null
    }

    # Pass CLI arguments to pfsense-backup; stderr and stdout both captured.
    # shellcheck disable=SC2317
    run_pfsense_backup_mixed() {
        local cmd_args=("$@")
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -e PFSENSE_HOST=fake-host \
            -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
            -e PFSENSE_IDENTITY_PASSWORD=testpassword \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
            "${IMAGE}" /usr/local/bin/pfsense-backup "${cmd_args[@]}" 2>&1
    }

    export -f run_pfsense_backup
    export -f run_pfsense_backup_mixed
}

# ── Info flags ────────────────────────────────────────────────────────────────

@test "--build-date exits 0" {
    run run_pfsense_backup_mixed --build-date
    [ "$status" -eq 0 ]
}

@test "--git-commit exits 0" {
    run run_pfsense_backup_mixed --git-commit
    [ "$status" -eq 0 ]
}

# ── Missing-argument guards ───────────────────────────────────────────────────

@test "-H without argument exits non-zero" {
    run run_pfsense_backup_mixed -H
    [ "$status" -ne 0 ]
}

@test "--host without argument exits non-zero" {
    run run_pfsense_backup_mixed --host
    [ "$status" -ne 0 ]
}

@test "--user without argument exits non-zero" {
    run run_pfsense_backup_mixed --user
    [ "$status" -ne 0 ]
}

@test "--identity-file without argument exits non-zero" {
    run run_pfsense_backup_mixed --identity-file
    [ "$status" -ne 0 ]
}

@test "--password without argument exits non-zero" {
    run run_pfsense_backup_mixed --password
    [ "$status" -ne 0 ]
}

@test "--password-file without argument exits non-zero" {
    run run_pfsense_backup_mixed --password-file
    [ "$status" -ne 0 ]
}

@test "--compression without argument exits non-zero" {
    run run_pfsense_backup_mixed --compression
    [ "$status" -ne 0 ]
}

@test "--bucket without argument exits non-zero" {
    run run_pfsense_backup_mixed --bucket
    [ "$status" -ne 0 ]
}

@test "--gpg-passphrase without argument exits non-zero" {
    run run_pfsense_backup_mixed --gpg-passphrase
    [ "$status" -ne 0 ]
}

@test "--cron-expression without argument exits non-zero" {
    run run_pfsense_backup_mixed --cron-expression
    [ "$status" -ne 0 ]
}

@test "--strict-host-key-checking without argument exits non-zero" {
    run run_pfsense_backup_mixed --strict-host-key-checking
    [ "$status" -ne 0 ]
}

@test "--known-hosts without argument exits non-zero" {
    run run_pfsense_backup_mixed --known-hosts
    [ "$status" -ne 0 ]
}

@test "--bucket-list without argument exits non-zero" {
    run run_pfsense_backup_mixed --bucket-list
    [ "$status" -ne 0 ]
}

@test "--aws-config without argument exits non-zero" {
    run run_pfsense_backup_mixed --aws-config
    [ "$status" -ne 0 ]
}

@test "--aws-extra-args without argument exits non-zero" {
    run run_pfsense_backup_mixed --aws-extra-args
    [ "$status" -ne 0 ]
}

@test "--gpg-cipher-algo without argument exits non-zero" {
    run run_pfsense_backup_mixed --gpg-cipher-algo
    [ "$status" -ne 0 ]
}

@test "--gpg-passphrase-file without argument exits non-zero" {
    run run_pfsense_backup_mixed --gpg-passphrase-file
    [ "$status" -ne 0 ]
}

# ── SSH options ───────────────────────────────────────────────────────────────

@test "--strict-host-key-checking no succeeds" {
    # With 'no', UserKnownHostsFile=/dev/null is used; no touch of known_hosts.
    run run_pfsense_backup_mixed --strict-host-key-checking no
    [ "$status" -eq 0 ]
}

@test "-P/--password-file CLI flag is accepted" {
    # Run inline: unset password env var and supply -P as a pfsense-backup arg.
    # shellcheck disable=SC2086
    run docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -v "${WHEREAMI}/bin:/test/bin:ro" \
        -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
        "${IMAGE}" /usr/local/bin/pfsense-backup \
        -P /test/fixtures/pfsense-identity-password
    [ "$status" -eq 0 ]
}

# ── Compression via CLI flag ──────────────────────────────────────────────────
# pfsense-backup stdout mode: XML (possibly compressed) written to stdout.
# Log messages go to stderr; run_pfsense_backup_mixed captures both.

@test "--compression gz CLI flag produces log with .xml.gz" {
    local output
    output=$(run_pfsense_backup_mixed --compression gz)
    echo "output: ${output}"
    [[ "${output}" == *".xml.gz"* ]]
}

@test "--compression xz CLI flag produces log with .xml.xz" {
    local output
    output=$(run_pfsense_backup_mixed --compression xz)
    echo "output: ${output}"
    [[ "${output}" == *".xml.xz"* ]]
}

@test "--compression none CLI flag succeeds" {
    run run_pfsense_backup_mixed --compression none
    [ "$status" -eq 0 ]
}

# ── Encryption via CLI flag ───────────────────────────────────────────────────

@test "--gpg-passphrase CLI flag encrypts backup" {
    local output
    output=$(run_pfsense_backup_mixed --gpg-passphrase secret)
    echo "output: ${output}"
    [[ "${output}" == *"encrypting backup with GPG"* ]]
    [[ "${output}" == *".xml.gpg"* ]]
}

@test "--gpg-passphrase-file CLI flag encrypts backup" {
    local output
    # shellcheck disable=SC2086
    output=$(docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword \
        -v "${WHEREAMI}/bin:/test/bin:ro" \
        -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
        "${IMAGE}" /usr/local/bin/pfsense-backup \
        --gpg-passphrase-file /test/fixtures/gpg-passphrase 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"encrypting backup with GPG"* ]]
    [[ "${output}" == *".xml.gpg"* ]]
}

# ── S3 upload via CLI flag ────────────────────────────────────────────────────

@test "-b/--bucket CLI flag triggers S3 upload" {
    local output
    # shellcheck disable=SC2086
    output=$(docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword \
        -v "${WHEREAMI}/bin:/test/bin:ro" \
        -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
        "${IMAGE}" /usr/local/bin/pfsense-backup \
        --bucket cli-test-bucket 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"cli-test-bucket"* ]]
    [[ "${output}" == *"aws s3 mv"* ]]
}

@test "-b alias works same as --bucket" {
    local output
    # shellcheck disable=SC2086
    output=$(docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword \
        -v "${WHEREAMI}/bin:/test/bin:ro" \
        -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
        "${IMAGE}" /usr/local/bin/pfsense-backup \
        -b cli-test-bucket 2>&1)
    echo "output: ${output}"
    [[ "${output}" == *"cli-test-bucket"* ]]
}

# ── stdout mode ───────────────────────────────────────────────────────────────

@test "stdout mode (no bucket) writes XML to stdout" {
    local output
    output=$(run_pfsense_backup)
    echo "output: ${output:0:200}"
    [[ "${output}" == *"<?xml"* ]]
}

@test "stdout mode output contains pfSense config content" {
    local output
    output=$(run_pfsense_backup)
    [[ "${output}" == *"<pfsense>"* ]]
}

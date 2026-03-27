#!/usr/bin/env bats
# test/02-pfsense-backup.bats — test src/pfsense-backup directly.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    WHEREAMI="${BATS_TEST_DIRNAME}"
    IMAGE="${IMAGE:-1121citrus/pfsense-backup:latest}"
    chmod +x "${WHEREAMI}/bin/"*
    export WHEREAMI IMAGE

    # Run pfsense-backup; extra docker flags go before IMAGE.
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

    # Run pfsense-backup passing CLI arguments to the command (not to docker).
    run_pfsense_backup_args() {
        local cmd_args=("$@")
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -e PFSENSE_HOST=fake-host \
            -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
            -e PFSENSE_IDENTITY_PASSWORD=testpassword \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
            "${IMAGE}" /usr/local/bin/pfsense-backup "${cmd_args[@]}" 2>/dev/null
    }

    export -f run_pfsense_backup
    export -f run_pfsense_backup_args
}

teardown() {
    if [ -n "${TEST_TMPDIR:-}" ]; then
        rm -rf "${TEST_TMPDIR}"
    fi
}

# ── Required-variable validation ─────────────────────────────────────────────

@test "exits non-zero when neither PFSENSE_HOST nor TAILSCALE_HOST is set" {
    run run_pfsense_backup -e PFSENSE_HOST= -e TAILSCALE_HOST=
    [ "$status" -ne 0 ]
}

@test "TAILSCALE_HOST accepted as fallback when PFSENSE_HOST is unset" {
    run run_pfsense_backup -e PFSENSE_HOST= -e TAILSCALE_HOST=tailscale-host
    [ "$status" -eq 0 ]
}

@test "exits non-zero when identity file does not exist" {
    run run_pfsense_backup -e PFSENSE_IDENTITY_FILE=/nonexistent/pfsense.key
    [ "$status" -ne 0 ]
}

@test "exits non-zero when no password is available" {
    run run_pfsense_backup \
        -e PFSENSE_IDENTITY_PASSWORD= \
        -e PFSENSE_IDENTITY_PASSWORD_FILE=/nonexistent/password
    [ "$status" -ne 0 ]
}

# ── XML output ────────────────────────────────────────────────────────────────

@test "stdout contains XML declaration" {
    local output
    output=$(run_pfsense_backup)
    echo "output (first 200): ${output:0:200}"
    echo "${output}" | grep -q '<?xml'
}

@test "output contains expected version element" {
    local output
    output=$(run_pfsense_backup)
    echo "output: ${output}"
    echo "${output}" | grep -q '<version>24.11</version>'
}

@test "output contains expected hostname element" {
    local output
    output=$(run_pfsense_backup)
    echo "output: ${output}"
    echo "${output}" | grep -q '<hostname>test-firewall</hostname>'
}

@test "name file contains expected filename pattern" {
    TEST_TMPDIR=$(mktemp -d)
    chmod o+w "${TEST_TMPDIR}"
    run_pfsense_backup \
        -e PFSENSE_BACKUP_NAME_FILE=/name/result \
        -v "${TEST_TMPDIR}:/name" > /dev/null
    local name
    name=$(cat "${TEST_TMPDIR}/result")
    echo "name: ${name}"
    [[ "${name}" == *"-pfsense-v"*"-config-backup.xml" ]]
}

# ── CLI flag tests ────────────────────────────────────────────────────────────

@test "--help exits 0 and prints usage" {
    local output
    output=$(run_pfsense_backup_args --help 2>&1)
    local status=$?
    echo "output: ${output}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Usage:"* ]]
}

@test "--version exits 0" {
    run run_pfsense_backup_args --version
    [ "$status" -eq 0 ]
}

@test "-H flag accepted as host" {
    run run_pfsense_backup_args -H fake-host
    [ "$status" -eq 0 ]
}

@test "exits non-zero for unknown option" {
    run run_pfsense_backup_args --no-such-option
    [ "$status" -ne 0 ]
}

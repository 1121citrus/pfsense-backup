#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2016  # single-quoted 'bash -c' strings expand in subshell
# test/13-source-coverage.bats — direct-execution coverage tests.
#
# Run source scripts directly (not via Docker) so kcov can instrument them.
# These tests complement the docker-based integration tests in 02–12 and are
# designed to exercise as many code paths as possible without network access
# or real hardware.
#
# Coverage targets:
#   src/common-functions  (31 lines)
#   src/pfsense-backup    (368 lines)
#   src/healthcheck       (42 lines)
#   src/backup            (9 lines)
#
# Note: src/startup contains a single exec line and is not directly
# instrumentable without /usr/local/bin/pfsense-backup on the test host.

setup() {
    REPO_ROOT=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
    TEST_BIN="${BATS_TEST_DIRNAME}/bin"
    TEST_FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
    TEST_TMPDIR=$(mktemp -d)
    export REPO_ROOT TEST_BIN TEST_FIXTURES TEST_TMPDIR
    export INCLUDE_DIR="${REPO_ROOT}/src"
    # Ensure mock tools (aws, ssh, sshpass, traceroute, supercronic) come first.
    export PATH="${TEST_BIN}:${PATH}"
    # Redirect log paths so scripts do not require /var/log.
    export PFSENSE_LOG_DIR="${TEST_TMPDIR}/log"
    export PFSENSE_LOG_FILE="${TEST_TMPDIR}/log/pfsense-backup.log"
    mkdir -p "${PFSENSE_LOG_DIR}"
    # Healthcheck marker files.
    export HEALTHCHECK_SUCCESS_FILE="${TEST_TMPDIR}/pfsense-backup.last-success"
    export HEALTHCHECK_STARTUP_FILE="${TEST_TMPDIR}/pfsense-backup.started-at"
    # Use a temp known-hosts file instead of /root/.ssh/known_hosts.
    export PFSENSE_SSH_KNOWN_HOSTS_FILE="${TEST_TMPDIR}/known_hosts"
    # Point the ssh mock to the test fixture.
    export SSH_FIXTURE_FILE="${TEST_FIXTURES}/config.xml"

    # Crontab directory for healthcheck tests.
    mkdir -p /var/spool/cron/crontabs

    # pgrep stub: simulate supercronic running (exit 0 always).
    STUB_DIR="${TEST_TMPDIR}/stubs"
    mkdir -p "${STUB_DIR}"
    printf '#!/bin/sh\nexec /bin/true\n' > "${STUB_DIR}/pgrep"
    chmod +x "${STUB_DIR}/pgrep"
    export STUB_DIR
}

teardown() {
    rm -rf "${TEST_TMPDIR:-}"
    rm -f "/var/spool/cron/crontabs/$(id -un)"
}

# ── src/common-functions ──────────────────────────────────────────────────────

@test "common-functions: is_true accepts 'true'" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; is_true "true"'
    [ "$status" -eq 0 ]
}

@test "common-functions: is_true accepts '1'" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; is_true "1"'
    [ "$status" -eq 0 ]
}

@test "common-functions: is_true accepts 'yes'" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; is_true "yes"'
    [ "$status" -eq 0 ]
}

@test "common-functions: is_true rejects 'false'" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; is_true "false"'
    [ "$status" -ne 0 ]
}

@test "common-functions: is_true rejects '0'" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; is_true "0"'
    [ "$status" -ne 0 ]
}

@test "common-functions: is_true rejects empty string" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; is_true ""'
    [ "$status" -ne 0 ]
}

@test "common-functions: path-append adds to end of PATH" {
    # Override PATH to a known value; include /bin so bash stays executable.
    result=$(INCLUDE_DIR="${INCLUDE_DIR}" PATH=/usr/bin:/bin \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; path-append /test/dir')
    [[ "${result}" == *":/test/dir" ]]
}

@test "common-functions: path-prepend adds to front of PATH" {
    result=$(INCLUDE_DIR="${INCLUDE_DIR}" PATH=/usr/bin:/bin \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; path-prepend /test/dir')
    [[ "${result}" == /test/dir:* ]]
}

@test "common-functions: path-remove removes a directory" {
    result=$(INCLUDE_DIR="${INCLUDE_DIR}" PATH=/test/dir:/usr/bin:/bin \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; path-remove /test/dir')
    [[ "${result}" != *"/test/dir"* ]]
    [[ "${result}" == *"/usr/bin"* ]]
}

@test "common-functions: error exits non-zero and logs to stderr" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; error "test error message"'
    [ "$status" -ne 0 ]
    [[ "$output" == *"test error message"* ]]
}

@test "common-functions: info logs message to stderr" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; info "test info message"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"test info message"* ]]
}

@test "common-functions: debug logs message to stderr" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash -c 'source "${INCLUDE_DIR}/common-functions"; debug "test debug message"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"test debug message"* ]]
}

# ── src/healthcheck ───────────────────────────────────────────────────────────

@test "healthcheck: exits non-zero when crontab is not configured" {
    # is_crontab_configured reads /var/spool/cron/crontabs/$(id -un).
    # On the test host this file does not exist → error → exits 1.
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        HEALTHCHECK_STARTUP_FILE="${HEALTHCHECK_STARTUP_FILE}" \
        HEALTHCHECK_MAX_AGE_SECONDS=300 \
        HEALTHCHECK_STARTUP_GRACE_SECONDS=300 \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -ne 0 ]
    [[ "$output" == *"crontab"* ]]
}

@test "healthcheck: exits non-zero when supercronic is not running" {
    printf '%s\n' '@daily /usr/local/bin/pfsense-backup' \
        > "/var/spool/cron/crontabs/$(id -un)"
    # Omit STUB_DIR from PATH so real pgrep finds no supercronic process.
    run env \
        DEBUG=true \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        HEALTHCHECK_STARTUP_FILE="${HEALTHCHECK_STARTUP_FILE}" \
        HEALTHCHECK_MAX_AGE_SECONDS=300 \
        HEALTHCHECK_STARTUP_GRACE_SECONDS=300 \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -ne 0 ]
    [[ "$output" == *"supercronic is not running"* ]]
}

@test "healthcheck: exits 0 when crontab ok, supercronic mocked, fresh success file" {
    printf '%s\n' '@daily /usr/local/bin/pfsense-backup' \
        > "/var/spool/cron/crontabs/$(id -un)"
    touch "${HEALTHCHECK_SUCCESS_FILE}"
    run env \
        DEBUG=true \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PATH="${STUB_DIR}:${PATH}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        HEALTHCHECK_STARTUP_FILE="${HEALTHCHECK_STARTUP_FILE}" \
        HEALTHCHECK_MAX_AGE_SECONDS=3600 \
        HEALTHCHECK_STARTUP_GRACE_SECONDS=900 \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -eq 0 ]
}

@test "healthcheck: exits 0 when within startup grace and no success file" {
    printf '%s\n' '@daily /usr/local/bin/pfsense-backup' \
        > "/var/spool/cron/crontabs/$(id -un)"
    touch "${HEALTHCHECK_STARTUP_FILE}"
    run env \
        DEBUG=true \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PATH="${STUB_DIR}:${PATH}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        HEALTHCHECK_STARTUP_FILE="${HEALTHCHECK_STARTUP_FILE}" \
        HEALTHCHECK_MAX_AGE_SECONDS=3600 \
        HEALTHCHECK_STARTUP_GRACE_SECONDS=3600 \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -eq 0 ]
}

@test "healthcheck: exits non-zero when success file is stale" {
    printf '%s\n' '@daily /usr/local/bin/pfsense-backup' \
        > "/var/spool/cron/crontabs/$(id -un)"
    touch -t 200001010000.00 "${HEALTHCHECK_SUCCESS_FILE}"
    run env \
        DEBUG=true \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PATH="${STUB_DIR}:${PATH}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        HEALTHCHECK_STARTUP_FILE="${HEALTHCHECK_STARTUP_FILE}" \
        HEALTHCHECK_MAX_AGE_SECONDS=1 \
        HEALTHCHECK_STARTUP_GRACE_SECONDS=1 \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -ne 0 ]
    [[ "$output" == *"too old"* ]]
}

@test "healthcheck: exits non-zero when startup grace is exceeded" {
    printf '%s\n' '@daily /usr/local/bin/pfsense-backup' \
        > "/var/spool/cron/crontabs/$(id -un)"
    touch -t 200001010000.00 "${HEALTHCHECK_STARTUP_FILE}"
    run env \
        DEBUG=true \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PATH="${STUB_DIR}:${PATH}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        HEALTHCHECK_STARTUP_FILE="${HEALTHCHECK_STARTUP_FILE}" \
        HEALTHCHECK_MAX_AGE_SECONDS=1 \
        HEALTHCHECK_STARTUP_GRACE_SECONDS=1 \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -ne 0 ]
    [[ "$output" == *"grace period exceeded"* ]]
}

@test "healthcheck: exits non-zero when no markers at all" {
    printf '%s\n' '@daily /usr/local/bin/pfsense-backup' \
        > "/var/spool/cron/crontabs/$(id -un)"
    run env \
        DEBUG=true \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PATH="${STUB_DIR}:${PATH}" \
        HEALTHCHECK_SUCCESS_FILE="${TEST_TMPDIR}/no-success-file" \
        HEALTHCHECK_STARTUP_FILE="${TEST_TMPDIR}/no-startup-file" \
        HEALTHCHECK_MAX_AGE_SECONDS=300 \
        HEALTHCHECK_STARTUP_GRACE_SECONDS=300 \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing both"* ]]
}

# ── src/backup ────────────────────────────────────────────────────────────────

@test "backup: exits non-zero when no bucket is configured" {
    run env \
        AWS_S3_BUCKET_NAME= \
        BUCKET= \
        BUCKET_LIST= \
        bash "${REPO_ROOT}/src/backup"
    [ "$status" -ne 0 ]
    [[ "$output" == *"need AWS_S3_BUCKET_NAME"* ]]
}

@test "backup: AWS_S3_BUCKET_NAME env satisfies the bucket check" {
    # The script detects the bucket and then execs /usr/local/bin/pfsense-backup
    # which may not exist on the test host; the exec failure (exit 127) is
    # expected and acceptable — what matters is that the "[ERROR] need bucket"
    # message is NOT emitted.
    run env \
        AWS_S3_BUCKET_NAME=test-bucket \
        BUCKET= \
        BUCKET_LIST= \
        bash "${REPO_ROOT}/src/backup"
    [[ "$output" != *"need AWS_S3_BUCKET_NAME"* ]]
}

@test "backup: --bucket flag satisfies the bucket check" {
    run env \
        AWS_S3_BUCKET_NAME= \
        BUCKET= \
        BUCKET_LIST= \
        bash "${REPO_ROOT}/src/backup" --bucket test-bucket
    [[ "$output" != *"need AWS_S3_BUCKET_NAME"* ]]
}

@test "backup: BUCKET_LIST env satisfies the bucket check" {
    run env \
        AWS_S3_BUCKET_NAME= \
        BUCKET= \
        BUCKET_LIST="bucket-a bucket-b" \
        bash "${REPO_ROOT}/src/backup"
    [[ "$output" != *"need AWS_S3_BUCKET_NAME"* ]]
}

# ── src/pfsense-backup: info flags ───────────────────────────────────────────

@test "pfsense-backup: --help exits 0 and shows Usage" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash "${REPO_ROOT}/src/pfsense-backup" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "pfsense-backup: -h exits 0" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash "${REPO_ROOT}/src/pfsense-backup" -h
    [ "$status" -eq 0 ]
}

@test "pfsense-backup: -? exits 0" {
    # shellcheck disable=SC2016
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash "${REPO_ROOT}/src/pfsense-backup" '-?'
    [ "$status" -eq 0 ]
}

@test "pfsense-backup: --version exits 0" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash "${REPO_ROOT}/src/pfsense-backup" --version
    [ "$status" -eq 0 ]
}

@test "pfsense-backup: -v exits 0" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash "${REPO_ROOT}/src/pfsense-backup" -v
    [ "$status" -eq 0 ]
}

@test "pfsense-backup: --build-date exits 0" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash "${REPO_ROOT}/src/pfsense-backup" --build-date
    [ "$status" -eq 0 ]
}

@test "pfsense-backup: --git-commit exits 0" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash "${REPO_ROOT}/src/pfsense-backup" --git-commit
    [ "$status" -eq 0 ]
}

# ── src/pfsense-backup: option parsing errors ─────────────────────────────────

@test "pfsense-backup: unknown option exits non-zero" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash "${REPO_ROOT}/src/pfsense-backup" --unknown-flag
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "pfsense-backup: unexpected positional argument exits non-zero" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash "${REPO_ROOT}/src/pfsense-backup" extra-arg
    [ "$status" -ne 0 ]
    [[ "$output" == *"unexpected argument"* ]]
}

@test "pfsense-backup: --host requires an argument" {
    run env INCLUDE_DIR="${INCLUDE_DIR}" \
        bash "${REPO_ROOT}/src/pfsense-backup" --host
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires an argument"* ]]
}

# ── src/pfsense-backup: missing required configuration ───────────────────────

@test "pfsense-backup: exits non-zero when no host configured" {
    # traceroute mock outputs nothing → resolve_host errors out.
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST= \
        TAILSCALE_HOST= \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup"
    [ "$status" -ne 0 ]
    [[ "$output" == *"need PFSENSE_HOST"* ]]
}

@test "pfsense-backup: exits non-zero when identity file is missing" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_TMPDIR}/no-such-key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        bash "${REPO_ROOT}/src/pfsense-backup"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found or is not readable"* ]]
}

@test "pfsense-backup: exits non-zero when no password configured" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD= \
        PFSENSE_IDENTITY_PASSWORD_FILE="${TEST_TMPDIR}/no-such-password-file" \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        bash "${REPO_ROOT}/src/pfsense-backup"
    [ "$status" -ne 0 ]
    [[ "$output" == *"PFSENSE_IDENTITY_PASSWORD"* ]]
}

# ── src/pfsense-backup: successful backup runs ───────────────────────────────

@test "pfsense-backup: stdout backup succeeds with mocked ssh" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        COMPRESSION=none \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup"
    [ "$status" -eq 0 ]
    [[ "$output" == *'<?xml'* ]]
}

@test "pfsense-backup: --host CLI flag overrides empty PFSENSE_HOST" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST= \
        TAILSCALE_HOST= \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        COMPRESSION=none \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup" --host fake-host
    [ "$status" -eq 0 ]
    [[ "$output" == *'<?xml'* ]]
}

@test "pfsense-backup: --user CLI flag is accepted" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        COMPRESSION=none \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup" --user custom-user
    [ "$status" -eq 0 ]
}

@test "pfsense-backup: --identity-file CLI flag overrides env" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_TMPDIR}/no-such-key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        COMPRESSION=none \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup" \
            --identity-file "${TEST_FIXTURES}/pfsense-identity.key"
    [ "$status" -eq 0 ]
}

@test "pfsense-backup: --password CLI flag is accepted" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD= \
        COMPRESSION=none \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup" --password testpassword
    [ "$status" -eq 0 ]
}

@test "pfsense-backup: --password-file CLI flag is accepted" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD= \
        COMPRESSION=none \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup" \
            --password-file "${TEST_FIXTURES}/pfsense-identity-password"
    [ "$status" -eq 0 ]
}

@test "pfsense-backup: --strict-host-key-checking no skips known_hosts" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        COMPRESSION=none \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup" --strict-host-key-checking no
    [ "$status" -eq 0 ]
}

@test "pfsense-backup: --dryrun flag is accepted" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=none \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup" --dryrun
    [ "$status" -eq 0 ]
    [[ "$output" == *"dryrun"* ]]
}

@test "pfsense-backup: S3 upload succeeds with mocked aws" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        AWS_S3_BUCKET_NAME=test-bucket \
        COMPRESSION=none \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"finish"* ]]
}

@test "pfsense-backup: multi-bucket upload via BUCKET_LIST" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        BUCKET_LIST="bucket-a bucket-b" \
        COMPRESSION=none \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"bucket-a"* ]]
    [[ "$output" == *"bucket-b"* ]]
}

@test "pfsense-backup: --bucket CLI flag activates S3 upload" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        COMPRESSION=none \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup" --bucket test-bucket
    [ "$status" -eq 0 ]
}

# ── src/pfsense-backup: compression variants ─────────────────────────────────

@test "pfsense-backup: gz compression succeeds" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        COMPRESSION=gz \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"compressing backup with gzip"* ]]
}

@test "pfsense-backup: bzip2 compression succeeds" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        COMPRESSION=bzip2 \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"compressing backup with bzip2"* ]]
}

@test "pfsense-backup: xz compression succeeds" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        COMPRESSION=xz \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        HEALTHCHECK_SUCCESS_FILE="${HEALTHCHECK_SUCCESS_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lzma/xz"* ]]
}

@test "pfsense-backup: invalid compression exits non-zero" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        COMPRESSION=badcompressor \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PFSENSE_SSH_KNOWN_HOSTS_FILE="${PFSENSE_SSH_KNOWN_HOSTS_FILE}" \
        SSH_FIXTURE_FILE="${SSH_FIXTURE_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown compression algorithm"* ]]
}

# ── src/pfsense-backup: scheduler mode ───────────────────────────────────────

@test "pfsense-backup: --cron exits non-zero without a bucket" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        AWS_S3_BUCKET_NAME= \
        BUCKET= \
        BUCKET_LIST= \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup" --cron
    [ "$status" -ne 0 ]
    [[ "$output" == *"BUCKET"* ]]
}

@test "pfsense-backup: CRON_EXPRESSION env implies scheduler mode" {
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        CRON_EXPRESSION="@daily" \
        AWS_S3_BUCKET_NAME= \
        BUCKET= \
        BUCKET_LIST= \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup"
    [ "$status" -ne 0 ]
    [[ "$output" == *"BUCKET"* ]]
}

@test "pfsense-backup: --cron with bucket writes env and execs supercronic" {
    # run_scheduler writes to /var/spool/cron/crontabs/$(id -un).
    # In the kcov container this path is writable as root.
    # On macOS the path likely does not exist; skip gracefully in that case.
    local crontab_dir="/var/spool/cron/crontabs"
    if [[ ! -d "${crontab_dir}" ]] || [[ ! -w "${crontab_dir}" ]]; then
        skip "crontab directory ${crontab_dir} not writable (not running as root)"
    fi
    local env_file="${TEST_TMPDIR}/.env"
    run env \
        INCLUDE_DIR="${INCLUDE_DIR}" \
        PFSENSE_HOST=fake-host \
        PFSENSE_IDENTITY_FILE="${TEST_FIXTURES}/pfsense-identity.key" \
        PFSENSE_IDENTITY_PASSWORD=testpassword \
        AWS_S3_BUCKET_NAME=test-bucket \
        ENV="${env_file}" \
        PFSENSE_BACKUP_CMD="${REPO_ROOT}/src/pfsense-backup" \
        PFSENSE_LOG_DIR="${PFSENSE_LOG_DIR}" \
        PFSENSE_LOG_FILE="${PFSENSE_LOG_FILE}" \
        HEALTHCHECK_STARTUP_FILE="${HEALTHCHECK_STARTUP_FILE}" \
        PATH="${PATH}" \
        bash "${REPO_ROOT}/src/pfsense-backup" --cron
    # supercronic mock exits 0; run_scheduler execs it so the whole script exits 0.
    [ "$status" -eq 0 ]
    [[ -f "${env_file}" ]]
}

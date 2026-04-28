#!/usr/bin/env bash
# shellcheck shell=bash

# test/staging-hooks.sh — repo-specific helpers and test implementations
# for the pfsense-backup staging harness (test/staging).
#
# Called by: test/staging (generated) via `source staging-hooks.sh`
# Provides:  setup_hooks() — docker-run helpers and pfSense credential mapping
#            test_staging_* — repo-specific test functions
#
# The generated test/staging provides: scan/advise tests, setup(), run_tests(),
# main(). This file provides only what is repo-specific.
#
# Generated harness variable mapping (generated → container env):
#   HOST                  → PFSENSE_HOST
#   REMOTE_USER           → PFSENSE_USER (default: remote-backup)
#   IDENTITY_FILE         → PFSENSE_IDENTITY_FILE
#   IDENTITY_PASSWORD_FILE → PFSENSE_IDENTITY_PASSWORD_FILE
#   DRYRUN                → AWS_DRYRUN (container uses AWS_DRYRUN)

# ---------------------------------------------------------------------------
# setup_hooks — defines docker-run helpers used by test functions.
# Called by setup() in the generated harness after credentials are ready.
# Exported env vars from setup(): _aws_cfg_mount, _aws_creds_mount, _scan_tar
# ---------------------------------------------------------------------------
setup_hooks() {
    # Map generated harness variable names to PFSENSE_* env vars expected by
    # the container.  This lets dev/bin/pfsense-backup-staging pass --host,
    # --identity-file, and --identity-password-file without knowing the
    # container's internal naming.
    export PFSENSE_HOST="${HOST:-}"
    export PFSENSE_USER="${REMOTE_USER:-remote-backup}"
    export PFSENSE_IDENTITY_FILE="${IDENTITY_FILE:-}"
    export PFSENSE_IDENTITY_PASSWORD_FILE="${IDENTITY_PASSWORD_FILE:-}"
    # DRYRUN in the harness controls S3; the container uses AWS_DRYRUN.
    export AWS_DRYRUN="${DRYRUN:-true}"

    export -f _append_pfsense_args run_backup _aws _healthcheck_run
}

# ---------------------------------------------------------------------------
# _append_pfsense_args — append pfSense credential flags to a named array.
#
# Handles the common mistake of setting PFSENSE_IDENTITY_PASSWORD to a file
# path instead of the actual passphrase string.  When the value is a readable
# path it is treated as PFSENSE_IDENTITY_PASSWORD_FILE.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2154  # PFSENSE_* exported by setup_hooks()
_append_pfsense_args() {
    local -n _ref=$1
    if [[ -n "${PFSENSE_HOST:-}" ]]; then
        _ref+=(-e "PFSENSE_HOST=${PFSENSE_HOST}")
        # Resolve hostname to IP so it works inside the container's network
        # namespace (containers cannot see the host's /etc/hosts or mDNS).
        if ! [[ "${PFSENSE_HOST}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            local _resolved
            _resolved=$(python3 -c \
                "import socket; print(socket.gethostbyname('${PFSENSE_HOST}'))" \
                2>/dev/null) \
                || _resolved=$(getent hosts "${PFSENSE_HOST}" 2>/dev/null \
                    | awk '{print $1; exit}') \
                || true
            [[ -n "${_resolved}" ]] && \
                _ref+=(--add-host "${PFSENSE_HOST}:${_resolved}")
        fi
    fi
    [[ -n "${PFSENSE_USER:-}" ]] && \
        _ref+=(-e "PFSENSE_USER=${PFSENSE_USER}")
    [[ -n "${PFSENSE_IDENTITY_FILE:-}" ]] && \
        _ref+=(-e "PFSENSE_IDENTITY_FILE=${PFSENSE_IDENTITY_FILE}" \
               -v "${PFSENSE_IDENTITY_FILE}:${PFSENSE_IDENTITY_FILE}:ro")
    if [[ -n "${PFSENSE_IDENTITY_PASSWORD:-}" ]]; then
        if [[ -r "${PFSENSE_IDENTITY_PASSWORD}" ]]; then
            _ref+=(-e "PFSENSE_IDENTITY_PASSWORD_FILE=${PFSENSE_IDENTITY_PASSWORD}" \
                   -v "${PFSENSE_IDENTITY_PASSWORD}:${PFSENSE_IDENTITY_PASSWORD}:ro")
        else
            _ref+=(-e "PFSENSE_IDENTITY_PASSWORD=${PFSENSE_IDENTITY_PASSWORD}")
        fi
    fi
    [[ -n "${PFSENSE_IDENTITY_PASSWORD_FILE:-}" ]] && \
        [[ -r "${PFSENSE_IDENTITY_PASSWORD_FILE}" ]] && \
        _ref+=(-e "PFSENSE_IDENTITY_PASSWORD_FILE=${PFSENSE_IDENTITY_PASSWORD_FILE}" \
               -v "${PFSENSE_IDENTITY_PASSWORD_FILE}:${PFSENSE_IDENTITY_PASSWORD_FILE}:ro")
}

# run_backup: docker run wrapper for the pfsense-backup backup script.
# Extra docker flags may be passed as arguments.
run_backup() {
    local extra_args=()
    _append_pfsense_args extra_args
    _append_aws_mounts extra_args
    [[ -n "${AWS_S3_BUCKET_NAME:-${S3_BUCKET_NAME:-}}" ]] && \
        extra_args+=(-e "AWS_S3_BUCKET_NAME=${AWS_S3_BUCKET_NAME:-${S3_BUCKET_NAME}}")
    [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && \
        extra_args+=(-e "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}" \
                     -e "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-}" \
                     -e "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-}")
    [[ -n "${AWS_DRYRUN:-}" ]] && \
        extra_args+=(-e "AWS_DRYRUN=${AWS_DRYRUN}")
    [[ -n "${COMPRESSION:-}" ]] && \
        extra_args+=(-e "COMPRESSION=${COMPRESSION}")
    # shellcheck disable=SC2086
    docker run --rm ${DOCKER_RUN_ARGS:-} "${extra_args[@]}" "$@" \
        -e "AWS_RETRY_MODE=standard" \
        -e "AWS_MAX_ATTEMPTS=5" \
        "${IMAGE}" /usr/local/bin/backup 2>&1
}

# _aws: run an aws CLI command inside the image, bypassing the backup entrypoint.
_aws() {
    local args=()
    _append_aws_mounts args
    # shellcheck disable=SC2086
    docker run --rm --entrypoint /usr/bin/aws \
        ${DOCKER_RUN_ARGS:-} \
        "${args[@]}" \
        -e "AWS_RETRY_MODE=standard" \
        -e "AWS_MAX_ATTEMPTS=5" \
        "${IMAGE}" "$@"
}

# _healthcheck_run: run /usr/local/bin/healthcheck inside the container after
# executing the given setup shell fragment.  Returns the docker exit code; all
# container output is suppressed.
_healthcheck_run() {
    local script="$1"; shift
    docker run --rm --entrypoint /bin/bash \
        "$@" \
        "${IMAGE}" -c "${script}" \
        >/dev/null 2>&1
}

# _pfsense_available: true when HOST and a usable credential exist.
_pfsense_available() {
    local pw_file="${PFSENSE_IDENTITY_PASSWORD_FILE:-/run/secrets/pfsense-identity-password}"
    [[ -n "${PFSENSE_HOST:-}" ]] && \
        [[ -n "${PFSENSE_IDENTITY_FILE:-}" ]] && \
        { [[ -n "${PFSENSE_IDENTITY_PASSWORD:-}" ]] || [[ -r "${pw_file}" ]]; }
}

# _aws_available: true when bucket and credentials are configured.
# shellcheck disable=SC2154  # _aws_cfg_mount/_aws_creds_mount exported by setup()
_pfsense_aws_available() {
    local bucket="${AWS_S3_BUCKET_NAME:-${S3_BUCKET_NAME:-}}"
    [[ -n "${bucket}" ]] && \
        { [[ -r "${_aws_cfg_mount:-/nonexistent}" ]] || \
          [[ -r "${_aws_creds_mount:-/nonexistent}" ]] || \
          [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; }
}

# _service_available: true when both pfSense and AWS are available.
_service_available() {
    _pfsense_available && _pfsense_aws_available
}

# ---------------------------------------------------------------------------
# Image-only tests (no live systems required)
# ---------------------------------------------------------------------------

test_staging_image_has_backup() {
    if docker run --rm --entrypoint /bin/sh \
           "${IMAGE}" -c 'test -x /usr/local/bin/backup'; then
        echo "PASS '${FUNCNAME[0]}': /usr/local/bin/backup exists and is executable"
    else
        echo "FAIL '${FUNCNAME[0]}': /usr/local/bin/backup missing or not executable"
        return 1
    fi
}

test_staging_image_has_pfsense_backup() {
    if docker run --rm --entrypoint /bin/sh \
           "${IMAGE}" -c 'test -x /usr/local/bin/pfsense-backup'; then
        echo "PASS '${FUNCNAME[0]}': /usr/local/bin/pfsense-backup exists and is executable"
    else
        echo "FAIL '${FUNCNAME[0]}': /usr/local/bin/pfsense-backup missing or not executable"
        return 1
    fi
}

test_staging_image_has_startup() {
    if docker run --rm --entrypoint /bin/sh \
           "${IMAGE}" -c 'test -x /usr/local/bin/startup'; then
        echo "PASS '${FUNCNAME[0]}': startup exists and is executable"
    else
        echo "FAIL '${FUNCNAME[0]}': startup missing or not executable"
        return 1
    fi
}

test_staging_image_has_healthcheck() {
    if docker run --rm --entrypoint /bin/sh \
           "${IMAGE}" -c 'test -x /usr/local/bin/healthcheck'; then
        echo "PASS '${FUNCNAME[0]}': /usr/local/bin/healthcheck exists and is executable"
    else
        echo "FAIL '${FUNCNAME[0]}': /usr/local/bin/healthcheck missing or not executable"
        return 1
    fi
}

test_staging_image_has_sshpass() {
    if docker run --rm --entrypoint /bin/sh \
           "${IMAGE}" -c 'command -v sshpass >/dev/null'; then
        echo "PASS '${FUNCNAME[0]}': sshpass is available in the image"
    else
        echo "FAIL '${FUNCNAME[0]}': sshpass not found"
        return 1
    fi
}

test_staging_image_has_ssh() {
    if docker run --rm --entrypoint /bin/sh \
           "${IMAGE}" -c 'command -v ssh >/dev/null'; then
        echo "PASS '${FUNCNAME[0]}': ssh is available in the image"
    else
        echo "FAIL '${FUNCNAME[0]}': ssh not found"
        return 1
    fi
}

test_staging_image_has_aws() {
    if docker run --rm --entrypoint /bin/sh \
           "${IMAGE}" -c 'command -v aws >/dev/null'; then
        echo "PASS '${FUNCNAME[0]}': aws cli is available in the image"
    else
        echo "FAIL '${FUNCNAME[0]}': aws cli not found"
        return 1
    fi
}

test_staging_missing_bucket_exits_nonzero() {
    local result=0
    docker run --rm "${IMAGE}" /usr/local/bin/backup \
        >/dev/null 2>&1 && result=0 || result=$?
    if [[ ${result} -ne 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': exits non-zero when AWS_S3_BUCKET_NAME is unset"
    else
        echo "FAIL '${FUNCNAME[0]}': should have exited non-zero"
        return 1
    fi
}

test_staging_missing_host_exits_nonzero() {
    local result=0
    docker run --rm \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        "${IMAGE}" /usr/local/bin/backup \
        >/dev/null 2>&1 && result=0 || result=$?
    if [[ ${result} -ne 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': exits non-zero when PFSENSE_HOST is unset"
    else
        echo "FAIL '${FUNCNAME[0]}': should have exited non-zero"
        return 1
    fi
}

test_staging_missing_identity_file_exits_nonzero() {
    local result=0
    docker run --rm \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e PFSENSE_HOST=192.0.2.1 \
        -e PFSENSE_IDENTITY_FILE=/nonexistent/pfsense.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword \
        "${IMAGE}" /usr/local/bin/backup \
        >/dev/null 2>&1 && result=0 || result=$?
    if [[ ${result} -ne 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': exits non-zero when identity file is missing"
    else
        echo "FAIL '${FUNCNAME[0]}': should have exited non-zero"
        return 1
    fi
}

test_staging_missing_password_exits_nonzero() {
    local result=0
    docker run --rm \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e PFSENSE_HOST=192.0.2.1 \
        -e PFSENSE_IDENTITY_FILE=/run/secrets/pfsense-identity \
        -e PFSENSE_IDENTITY_PASSWORD= \
        -e PFSENSE_IDENTITY_PASSWORD_FILE=/nonexistent/password \
        "${IMAGE}" /usr/local/bin/backup \
        >/dev/null 2>&1 && result=0 || result=$?
    if [[ ${result} -ne 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': exits non-zero when no credential is supplied"
    else
        echo "FAIL '${FUNCNAME[0]}': should have exited non-zero"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Healthcheck tests (image-only)
# ---------------------------------------------------------------------------

# Shell fragments executed inside the container via bash -c.
# Single-quoted so that $(id -un) is NOT expanded by the host shell.
# shellcheck disable=SC2016,SC2089
_HC_CRONTAB='printf "SHELL=/bin/sh\n* * * * * /usr/local/bin/pfsense-backup\n" > /var/spool/cron/crontabs/$(id -un)'
# shellcheck disable=SC2016,SC2089
_HC_SUPERCRONIC='touch /var/spool/cron/crontabs/$(id -un) && supercronic /var/spool/cron/crontabs/$(id -un) >/dev/null 2>&1 & sleep 0.5'

test_staging_healthcheck_healthy() {
    local result=0
    # shellcheck disable=SC2090
    _healthcheck_run \
        "${_HC_CRONTAB} && ${_HC_SUPERCRONIC} && touch /tmp/hc-success && /usr/local/bin/healthcheck" \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/hc-success \
        -e HEALTHCHECK_MAX_AGE_SECONDS=300 \
        -e HEALTHCHECK_STARTUP_GRACE_SECONDS=300 \
        && result=0 || result=$?
    if [[ ${result} -eq 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': healthcheck exits 0 when fully healthy"
    else
        echo "FAIL '${FUNCNAME[0]}': expected exit 0, got ${result}"
        return 1
    fi
}

test_staging_healthcheck_unhealthy_no_crontab() {
    local result=0
    # shellcheck disable=SC2090
    _healthcheck_run \
        "${_HC_SUPERCRONIC} && touch /tmp/hc-success && /usr/local/bin/healthcheck" \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/hc-success \
        -e HEALTHCHECK_MAX_AGE_SECONDS=300 \
        && result=0 || result=$?
    if [[ ${result} -ne 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': healthcheck exits non-zero when crontab is missing"
    else
        echo "FAIL '${FUNCNAME[0]}': expected non-zero exit, got 0"
        return 1
    fi
}

test_staging_healthcheck_unhealthy_no_supercronic() {
    local result=0
    # shellcheck disable=SC2090
    _healthcheck_run \
        "${_HC_CRONTAB} && touch /tmp/hc-success && /usr/local/bin/healthcheck" \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/hc-success \
        -e HEALTHCHECK_MAX_AGE_SECONDS=300 \
        && result=0 || result=$?
    if [[ ${result} -ne 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': healthcheck exits non-zero when supercronic is not running"
    else
        echo "FAIL '${FUNCNAME[0]}': expected non-zero exit, got 0"
        return 1
    fi
}

test_staging_healthcheck_healthy_grace_period() {
    local result=0
    # shellcheck disable=SC2090
    _healthcheck_run \
        "${_HC_CRONTAB} && ${_HC_SUPERCRONIC} && touch /tmp/hc-started && /usr/local/bin/healthcheck" \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/hc-success-absent \
        -e HEALTHCHECK_STARTUP_FILE=/tmp/hc-started \
        -e HEALTHCHECK_MAX_AGE_SECONDS=300 \
        -e HEALTHCHECK_STARTUP_GRACE_SECONDS=300 \
        && result=0 || result=$?
    if [[ ${result} -eq 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': healthcheck exits 0 within startup grace period"
    else
        echo "FAIL '${FUNCNAME[0]}': expected exit 0, got ${result}"
        return 1
    fi
}

test_staging_healthcheck_unhealthy_stale_backup() {
    local result=0
    # shellcheck disable=SC2090
    _healthcheck_run \
        "${_HC_CRONTAB} && ${_HC_SUPERCRONIC} && touch /tmp/hc-old-success && /usr/local/bin/healthcheck" \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/hc-old-success \
        -e HEALTHCHECK_MAX_AGE_SECONDS=-1 \
        -e HEALTHCHECK_STARTUP_GRACE_SECONDS=-1 \
        && result=0 || result=$?
    if [[ ${result} -ne 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': healthcheck exits non-zero when backup marker is too old"
    else
        echo "FAIL '${FUNCNAME[0]}': expected non-zero exit, got 0"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# pfSense-dependent tests (require PFSENSE_HOST + identity)
# ---------------------------------------------------------------------------

test_staging_backup_downloads_config() {
    _pfsense_available || { _skip "PFSENSE_HOST / identity not configured"; return 0; }
    local output result=0
    output=$(run_backup -e DRYRUN=true 2>&1) && result=0 || result=$?
    if [[ ${result} -eq 0 ]] && [[ "${output}" == *'finish backup'* ]]; then
        echo "PASS '${FUNCNAME[0]}': backup completed against live pfSense"
    else
        echo "FAIL '${FUNCNAME[0]}': expected 'finish backup' in output"
        printf '%s\n' "${output}" | tail -20 >&2
        return 1
    fi
}

test_staging_backup_xml_has_expected_fields() {
    _pfsense_available || { _skip "PFSENSE_HOST / identity not configured"; return 0; }
    local output result=0
    output=$(run_backup -e DRYRUN=true 2>&1) && result=0 || result=$?
    if [[ ${result} -eq 0 ]] && \
       [[ "${output}" == *'-pfsense-v'* ]] && \
       [[ "${output}" == *'-config-backup.xml'* ]]; then
        echo "PASS '${FUNCNAME[0]}': backup filename contains hostname and version fields"
    else
        echo "FAIL '${FUNCNAME[0]}': expected hostname/version in backup filename"
        printf '%s\n' "${output}" | tail -20 >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Full pipeline tests (pfSense + AWS)
# ---------------------------------------------------------------------------

test_staging_backup_direct() {
    _service_available || { _skip "pfSense or AWS not configured"; return 0; }

    local tmpout
    tmpout=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '${tmpout}'" RETURN

    run_backup >"${tmpout}" 2>&1 &
    local pid=$!

    local elapsed=0 interval=10 timeout=300
    while kill -0 "${pid}" 2>/dev/null; do
        sleep "${interval}"
        elapsed=$(( elapsed + interval ))
        printf '[%ds] backup in progress...\n' "${elapsed}"
        if (( elapsed >= timeout )); then
            kill "${pid}" 2>/dev/null || true
            echo "FAIL '${FUNCNAME[0]}': timed out after ${timeout}s"
            cat "${tmpout}" >&2
            return 1
        fi
    done
    local result
    wait "${pid}" && result=0 || result=$?

    if [[ ${result} -eq 0 ]] && grep -q 'finish backup' "${tmpout}"; then
        echo "PASS '${FUNCNAME[0]}': end-to-end backup completed"
    else
        echo "FAIL '${FUNCNAME[0]}': backup exited ${result} or did not finish cleanly"
        cat "${tmpout}" >&2
        return 1
    fi
}


test_staging_cron_fires() {
    _service_available || { _skip "pfSense or AWS not configured"; return 0; }

    local container extra_env=()
    _append_pfsense_args extra_env
    _append_aws_mounts extra_env
    [[ -n "${AWS_S3_BUCKET_NAME:-${S3_BUCKET_NAME:-}}" ]] && \
        extra_env+=(-e "AWS_S3_BUCKET_NAME=${AWS_S3_BUCKET_NAME:-${S3_BUCKET_NAME}}")
    [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && \
        extra_env+=(-e "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}" \
                    -e "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-}" \
                    -e "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-}")
    [[ -n "${AWS_DRYRUN:-}" ]] && \
        extra_env+=(-e "AWS_DRYRUN=${AWS_DRYRUN}")

    # shellcheck disable=SC2086
    container=$(docker run --detach \
        -e "CRON_EXPRESSION=* * * * *" \
        -e "AWS_RETRY_MODE=standard" \
        -e "AWS_MAX_ATTEMPTS=5" \
        ${DOCKER_RUN_ARGS:-} \
        "${extra_env[@]}" \
        "${IMAGE}")
    # shellcheck disable=SC2064
    trap "docker rm --force '${container}' >/dev/null 2>&1 || true" RETURN

    local result=0
    _wait_for_log_pattern "${container}" 'finish backup' 240 || result=$?
    if [[ ${result} -eq 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': cron job fired and backup completed (${_WAIT_ELAPSED}s)"
    else
        echo "FAIL '${FUNCNAME[0]}': timed out after 240s waiting for cron backup"
        return 1
    fi
}

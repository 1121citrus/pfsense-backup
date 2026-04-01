#!/usr/bin/env bats
# test/11-scheduler-mode.bats — test scheduler mode entry and error handling.
#
# Covers: --cron, --cron-expression, CRON_EXPRESSION env, --hourly/daily/weekly/
# monthly/yearly flags triggering scheduler mode, and the missing-bucket error
# that run_scheduler emits before exec'ing supercronic.
#
# Tests use a stubbed `supercronic` from `test/bin/` so scheduler mode can
# reach the handoff path and terminate cleanly in CI.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    WHEREAMI="${BATS_TEST_DIRNAME}"
    IMAGE="${IMAGE:-1121citrus/pfsense-backup:latest}"
    chmod +x "${WHEREAMI}/bin/"*
    export WHEREAMI IMAGE

    # Run pfsense-backup with fixed connection env and CLI args after IMAGE.
    # Captures stdout+stderr together.
    run_sched() {
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -e PFSENSE_HOST=fake-host \
            -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
            -e PFSENSE_IDENTITY_PASSWORD=testpassword \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
            "$@" \
            "${IMAGE}" /usr/local/bin/pfsense-backup 2>&1
    }

    # Run with CLI arguments appended to the command.
    run_sched_args() {
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

    export -f run_sched
    export -f run_sched_args
}

# ── Scheduler mode requires a bucket ─────────────────────────────────────────

@test "--cron without bucket exits non-zero" {
    run run_sched_args --cron
    [ "$status" -ne 0 ]
}

@test "--cron without bucket reports bucket requirement" {
    run run_sched_args --cron
    [ "$status" -ne 0 ]
    [[ "$output" == *"BUCKET"* ]] || [[ "$output" == *"bucket"* ]]
}

@test "--cron-expression '@daily' without bucket exits non-zero" {
    run run_sched_args --cron-expression '@daily'
    [ "$status" -ne 0 ]
}

@test "CRON_EXPRESSION env without bucket exits non-zero" {
    run run_sched -e CRON_EXPRESSION=@daily
    [ "$status" -ne 0 ]
}

@test "CRON_EXPRESSION env implies scheduler mode (bucket error, not host error)" {
    # With CRON_EXPRESSION set, we enter scheduler mode before the host check.
    # The error should be about the missing bucket, not missing host.
    run docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        -e CRON_EXPRESSION=@daily \
        -v "${WHEREAMI}/bin:/test/bin:ro" \
        -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
        "${IMAGE}" /usr/local/bin/pfsense-backup 2>&1
    [ "$status" -ne 0 ]
    [[ "$output" == *"BUCKET"* ]] || [[ "$output" == *"bucket"* ]]
}

# ── Policy flags trigger scheduler mode ──────────────────────────────────────

@test "--hourly without bucket exits non-zero" {
    run run_sched_args --hourly 12
    [ "$status" -ne 0 ]
}

@test "--daily without bucket exits non-zero" {
    run run_sched_args --daily 7
    [ "$status" -ne 0 ]
}

@test "--weekly without bucket exits non-zero" {
    run run_sched_args --weekly 4
    [ "$status" -ne 0 ]
}

@test "--monthly without bucket exits non-zero" {
    run run_sched_args --monthly 6
    [ "$status" -ne 0 ]
}

@test "--yearly without bucket exits non-zero" {
    run run_sched_args --yearly 1
    [ "$status" -ne 0 ]
}

# ── Policy flag missing-argument guards ──────────────────────────────────────

@test "--hourly without argument exits non-zero" {
    run run_sched_args --hourly
    [ "$status" -ne 0 ]
}

@test "--daily without argument exits non-zero" {
    run run_sched_args --daily
    [ "$status" -ne 0 ]
}

@test "--weekly without argument exits non-zero" {
    run run_sched_args --weekly
    [ "$status" -ne 0 ]
}

@test "--monthly without argument exits non-zero" {
    run run_sched_args --monthly
    [ "$status" -ne 0 ]
}

@test "--yearly without argument exits non-zero" {
    run run_sched_args --yearly
    [ "$status" -ne 0 ]
}

# ── Scheduler mode log messages ───────────────────────────────────────────────

@test "--cron logs 'entering scheduler mode'" {
    run docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword \
        -e BUCKET=test-bucket \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e PFSENSE_BACKUP_CMD=/bin/true \
        -v "${WHEREAMI}/bin:/test/bin:ro" \
        -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
        "${IMAGE}" /usr/local/bin/pfsense-backup --cron 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"scheduler mode"* ]]
    [[ "$output" == *"handing off to supercronic"* ]]
    [[ "$output" == *"supercronic stub invoked"* ]]
}

@test "--cron writes a supercronic schedule file" {
    run docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword \
        -e BUCKET=test-bucket \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e PFSENSE_BACKUP_CMD=/bin/true \
        -v "${WHEREAMI}/bin:/test/bin:ro" \
        -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
        "${IMAGE}" /usr/local/bin/pfsense-backup --cron 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHELL=/bin/sh"* ]]
    [[ "$output" == *"/bin/true"* ]]
}

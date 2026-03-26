#!/usr/bin/env bats
# test/08-healthcheck.bats — test all healthcheck scenarios.
#
# Uses --entrypoint /bin/bash to configure container state before invoking
# /usr/local/bin/healthcheck.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

# Shell fragments run inside the container to configure crond and cron table.
CROND_START='crond -l 2 & sleep 0.5'
CRONTAB_SETUP='mkdir -p /var/spool/cron/crontabs && printf "%s\n" "* * * * * /usr/local/bin/backup 2>&1" > /var/spool/cron/crontabs/root'

setup() {
    IMAGE="${IMAGE:-1121citrus/pfsense-backup:latest}"
    export IMAGE CROND_START CRONTAB_SETUP

    run_healthcheck() {
        # $1: shell -c script; remaining args: extra docker run flags
        local script=$1; shift
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            --entrypoint /bin/bash \
            "$@" \
            "${IMAGE}" \
            -c "${script}" >/dev/null 2>&1
    }
    export -f run_healthcheck
}

@test "healthy when crond running, crontab set, and fresh backup marker present" {
    run run_healthcheck \
        "${CROND_START} && ${CRONTAB_SETUP} && touch /tmp/hc-success && /usr/local/bin/healthcheck" \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/hc-success \
        -e HEALTHCHECK_MAX_AGE_SECONDS=300 \
        -e HEALTHCHECK_STARTUP_GRACE_SECONDS=300
    [ "$status" -eq 0 ]
}

@test "unhealthy when crontab is not configured" {
    run run_healthcheck \
        "${CROND_START} && touch /tmp/hc-success && /usr/local/bin/healthcheck" \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/hc-success \
        -e HEALTHCHECK_MAX_AGE_SECONDS=300
    [ "$status" -ne 0 ]
}

@test "unhealthy when crond is not running" {
    run run_healthcheck \
        "${CRONTAB_SETUP} && touch /tmp/hc-success && /usr/local/bin/healthcheck" \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/hc-success \
        -e HEALTHCHECK_MAX_AGE_SECONDS=300
    [ "$status" -ne 0 ]
}

@test "unhealthy when backup marker exceeds MAX_AGE_SECONDS" {
    run run_healthcheck \
        "${CROND_START} && ${CRONTAB_SETUP} && touch /tmp/hc-success && /usr/local/bin/healthcheck" \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/hc-success \
        -e HEALTHCHECK_MAX_AGE_SECONDS=-1 \
        -e HEALTHCHECK_STARTUP_GRACE_SECONDS=-1
    [ "$status" -ne 0 ]
}

@test "healthy when no backup yet but within startup grace period" {
    run run_healthcheck \
        "${CROND_START} && ${CRONTAB_SETUP} && touch /tmp/hc-started && /usr/local/bin/healthcheck" \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/hc-success-absent \
        -e HEALTHCHECK_STARTUP_FILE=/tmp/hc-started \
        -e HEALTHCHECK_MAX_AGE_SECONDS=300 \
        -e HEALTHCHECK_STARTUP_GRACE_SECONDS=300
    [ "$status" -eq 0 ]
}

@test "unhealthy when startup grace has expired and no backup ran" {
    run run_healthcheck \
        "${CROND_START} && ${CRONTAB_SETUP} && touch /tmp/hc-started && /usr/local/bin/healthcheck" \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/hc-success-absent \
        -e HEALTHCHECK_STARTUP_FILE=/tmp/hc-started \
        -e HEALTHCHECK_STARTUP_GRACE_SECONDS=-1
    [ "$status" -ne 0 ]
}

@test "healthy when stale marker exists but startup grace is still active (restart scenario)" {
    # Regression: old code errored on stale marker without checking grace period.
    run run_healthcheck \
        "${CROND_START} && ${CRONTAB_SETUP} && touch /tmp/hc-stale-success && touch /tmp/hc-started && /usr/local/bin/healthcheck" \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/hc-stale-success \
        -e HEALTHCHECK_STARTUP_FILE=/tmp/hc-started \
        -e HEALTHCHECK_MAX_AGE_SECONDS=-1 \
        -e HEALTHCHECK_STARTUP_GRACE_SECONDS=300
    [ "$status" -eq 0 ]
}

@test "unhealthy when both startup and success markers are absent" {
    run run_healthcheck \
        "${CROND_START} && ${CRONTAB_SETUP} && /usr/local/bin/healthcheck" \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/hc-success-absent \
        -e HEALTHCHECK_STARTUP_FILE=/tmp/hc-started-absent
    [ "$status" -ne 0 ]
}

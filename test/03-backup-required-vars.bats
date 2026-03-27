#!/usr/bin/env bats
# test/03-backup-required-vars.bats — test required-variable validation.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    WHEREAMI="${BATS_TEST_DIRNAME}"
    IMAGE="${IMAGE:-1121citrus/pfsense-backup:latest}"
    chmod +x "${WHEREAMI}/bin/"*
    export WHEREAMI IMAGE

    run_backup() {
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
            -v "${WHEREAMI}/fixtures/test-path.sh:/etc/profile.d/test-path.sh:ro" \
            "$@" \
            "${IMAGE}" /usr/local/bin/backup 2>&1
    }
    export -f run_backup
}

@test "exits non-zero when AWS_S3_BUCKET_NAME is unset" {
    run run_backup \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword
    [ "$status" -ne 0 ]
}

@test "exits non-zero when PFSENSE_HOST and TAILSCALE_HOST are unset" {
    run run_backup \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword
    [ "$status" -ne 0 ]
}

@test "exits non-zero when identity file does not exist" {
    run run_backup \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/nonexistent/pfsense.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword
    [ "$status" -ne 0 ]
}

@test "exits non-zero when neither password nor password file is provided" {
    run run_backup \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -e PFSENSE_IDENTITY_PASSWORD= \
        -e PFSENSE_IDENTITY_PASSWORD_FILE=/nonexistent/password
    [ "$status" -ne 0 ]
}

@test "exits non-zero on unknown COMPRESSION value" {
    run run_backup \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword \
        -e COMPRESSION=badcompressor
    [ "$status" -ne 0 ]
}

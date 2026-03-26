#!/usr/bin/env bats
# test/06-backup-aws-failure.bats — test AWS S3 upload failure handling.
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
            -e AWS_S3_BUCKET_NAME=test-bucket \
            -e PFSENSE_HOST=fake-host \
            -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
            -e PFSENSE_IDENTITY_PASSWORD=testpassword \
            -e COMPRESSION=none \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
            -v "${WHEREAMI}/fixtures/test-path.sh:/etc/profile.d/test-path.sh:ro" \
            "$@" \
            "${IMAGE}" /usr/local/bin/backup 2>&1
    }
    export -f run_backup
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && rm -rf "${TEST_TMPDIR}"
}

@test "exits non-zero when aws s3 mv fails" {
    run run_backup -e AWS_EXIT_CODE=1
    [ "$status" -ne 0 ]
}

@test "healthcheck success marker is not created on aws upload failure" {
    TEST_TMPDIR=$(mktemp -d)
    # shellcheck disable=SC2086
    docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword \
        -e COMPRESSION=none \
        -e AWS_EXIT_CODE=1 \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/markers/last-success \
        -v "${WHEREAMI}/bin:/test/bin:ro" \
        -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
        -v "${WHEREAMI}/fixtures/test-path.sh:/etc/profile.d/test-path.sh:ro" \
        -v "${TEST_TMPDIR}:/tmp/markers" \
        "${IMAGE}" /usr/local/bin/backup >/dev/null 2>&1 || true
    echo "marker exists: $(ls -la "${TEST_TMPDIR}/" 2>&1 || true)"
    [ ! -f "${TEST_TMPDIR}/last-success" ]
}

@test "error output contains 'aws s3 mv failed'" {
    run run_backup -e AWS_EXIT_CODE=1
    echo "output: $output"
    [ "$status" -ne 0 ]
    [[ "$output" == *"aws s3 mv failed"* ]]
}

@test "healthcheck success marker is created on successful backup" {
    TEST_TMPDIR=$(mktemp -d)
    # shellcheck disable=SC2086
    docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword \
        -e COMPRESSION=none \
        -e HEALTHCHECK_SUCCESS_FILE=/tmp/markers/last-success \
        -v "${WHEREAMI}/bin:/test/bin:ro" \
        -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
        -v "${WHEREAMI}/fixtures/test-path.sh:/etc/profile.d/test-path.sh:ro" \
        -v "${TEST_TMPDIR}:/tmp/markers" \
        "${IMAGE}" /usr/local/bin/backup >/dev/null 2>&1
    echo "marker listing: $(ls -la "${TEST_TMPDIR}/" 2>&1 || true)"
    [ -f "${TEST_TMPDIR}/last-success" ]
}

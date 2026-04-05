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

@test "exits non-zero when aws s3 mv fails" {
    run run_backup -e AWS_EXIT_CODE=1
    [ "$status" -ne 0 ]
}

@test "healthcheck success marker is not created on aws upload failure" {
    # Check the marker inside the container — avoids bind-mount path issues in DinD.
    # The backup fails (AWS_EXIT_CODE=1), so the marker must be absent.
    # shellcheck disable=SC2086
    run docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        --entrypoint /bin/bash \
        -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword \
        -e COMPRESSION=none \
        -e AWS_EXIT_CODE=1 \
        -v "${WHEREAMI}/bin:/test/bin:ro" \
        -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
        -v "${WHEREAMI}/fixtures/test-path.sh:/etc/profile.d/test-path.sh:ro" \
        "${IMAGE}" \
        -c '/usr/local/bin/backup >/dev/null 2>&1 || true
            test ! -f /tmp/pfsense-backup.last-success'
    [ "$status" -eq 0 ]
}

@test "error output contains 'aws s3 mv failed'" {
    run run_backup -e AWS_EXIT_CODE=1
    echo "output: $output"
    [ "$status" -ne 0 ]
    [[ "$output" == *"aws s3 mv failed"* ]]
}

@test "healthcheck success marker is created on successful backup" {
    # Check the marker inside the container — avoids bind-mount path issues in DinD.
    # The backup succeeds, so the marker must be present.
    # shellcheck disable=SC2086
    run docker run -i --rm ${DOCKER_RUN_ARGS:-} \
        --entrypoint /bin/bash \
        -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        -e AWS_S3_BUCKET_NAME=test-bucket \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword \
        -e COMPRESSION=none \
        -v "${WHEREAMI}/bin:/test/bin:ro" \
        -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
        -v "${WHEREAMI}/fixtures/test-path.sh:/etc/profile.d/test-path.sh:ro" \
        "${IMAGE}" \
        -c '/usr/local/bin/backup >/dev/null 2>&1
            test -f /tmp/pfsense-backup.last-success'
    [ "$status" -eq 0 ]
}
 

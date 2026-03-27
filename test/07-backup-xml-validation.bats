#!/usr/bin/env bats
# test/07-backup-xml-validation.bats — test XML field validation in src/backup.
#
# SSH_FIXTURE_FILE is forwarded to the ssh stub to select a specific fixture.
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

@test "exits non-zero and reports 'missing version' for config without version element" {
    run run_backup -e SSH_FIXTURE_FILE=/test/fixtures/config-missing-version.xml
    echo "output: $output"
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing version"* ]]
}

@test "exits non-zero and reports 'missing hostname' for config without hostname element" {
    run run_backup -e SSH_FIXTURE_FILE=/test/fixtures/config-missing-hostname.xml
    echo "output: $output"
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing hostname"* ]]
}

@test "exits non-zero and reports 'missing domain' for config without domain element" {
    run run_backup -e SSH_FIXTURE_FILE=/test/fixtures/config-missing-domain.xml
    echo "output: $output"
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing domain"* ]]
}

@test "backup filename contains host, version, and suffix for valid XML" {
    local output
    output=$(run_backup)
    echo "output: ${output}"
    [[ "${output}" =~ test-firewall-pfsense-v24\.11-config-backup\.xml ]]
}

#!/usr/bin/env bats
# test/05-backup-encryption.bats — test GPG encryption of backups.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    WHEREAMI="${BATS_TEST_DIRNAME}"
    IMAGE="${IMAGE:-1121citrus/pfsense-backup:latest}"
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

@test "GPG_PASSPHRASE encrypts backup and produces .xml.gpg extension" {
    local output
    output=$(run_backup -e GPG_PASSPHRASE=secret)
    echo "output: ${output}"
    [[ "${output}" == *"encrypting backup with GPG"* ]]
    [[ "${output}" == *".xml.gpg"* ]]
}

@test "passphrase with spaces is accepted" {
    local output
    output=$(run_backup -e "GPG_PASSPHRASE=correct horse battery staple")
    echo "output: ${output}"
    [[ "${output}" == *"encrypting backup with GPG"* ]]
    [[ "${output}" == *".xml.gpg"* ]]
}

@test "GPG_PASSPHRASE_FILE uses passphrase from file" {
    local output
    output=$(run_backup \
        -e GPG_PASSPHRASE_FILE=/test/fixtures/gpg-passphrase \
        -v "${WHEREAMI}/fixtures:/test/fixtures:ro")
    echo "output: ${output}"
    [[ "${output}" == *"encrypting backup with GPG"* ]]
    [[ "${output}" == *".xml.gpg"* ]]
}

@test "xz compression with GPG produces .xml.xz.gpg extension" {
    local output
    output=$(run_backup -e COMPRESSION=xz -e GPG_PASSPHRASE=secret)
    echo "output: ${output}"
    [[ "${output}" == *".xml.xz.gpg"* ]]
}

@test "backup without passphrase does not encrypt" {
    local output
    output=$(run_backup)
    echo "output: ${output}"
    [[ "${output}" != *"encrypting backup with GPG"* ]]
}

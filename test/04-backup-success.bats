#!/usr/bin/env bats
# test/04-backup-success.bats — test successful backup paths with each compression mode.
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
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
            -v "${WHEREAMI}/fixtures/test-path.sh:/etc/profile.d/test-path.sh:ro" \
            "$@" \
            "${IMAGE}" /usr/local/bin/backup 2>&1
    }
    export -f run_backup
}

@test "no-compression backup begins and finishes" {
    local output
    output=$(run_backup -e COMPRESSION=none)
    echo "output: ${output}"
    [[ "${output}" == *"begin backup"* ]]
    [[ "${output}" == *"finish backup"* ]]
    [[ "${output}" == *"aws s3 mv"* ]]
    [[ "${output}" == *"test-firewall-pfsense-v24.11-config-backup.xml"* ]]
    [[ "${output}" == *"test-bucket"* ]]
}

@test "identity password with spaces does not break backup" {
    local output
    output=$(run_backup \
        -e "PFSENSE_IDENTITY_PASSWORD=test password with spaces" \
        -e COMPRESSION=none)
    echo "output: ${output}"
    [[ "${output}" == *"begin backup"* ]]
    [[ "${output}" == *"finish backup"* ]]
}

@test "gz compression logs and produces .xml.gz extension" {
    local output
    output=$(run_backup -e COMPRESSION=gz)
    echo "output: ${output}"
    [[ "${output}" == *"compressing backup with gzip"* ]]
    [[ "${output}" == *".xml.gz"* ]]
}

@test "gzip alias produces .xml.gz extension" {
    local output
    output=$(run_backup -e COMPRESSION=gzip)
    echo "output: ${output}"
    [[ "${output}" == *".xml.gz"* ]]
}

@test "xz compression logs and produces .xml.xz extension" {
    local output
    output=$(run_backup -e COMPRESSION=xz)
    echo "output: ${output}"
    [[ "${output}" == *"compressing backup with lzma/xz"* ]]
    [[ "${output}" == *".xml.xz"* ]]
}

@test "lzma alias produces .xml.xz extension" {
    local output
    output=$(run_backup -e COMPRESSION=lzma)
    echo "output: ${output}"
    [[ "${output}" == *".xml.xz"* ]]
}

@test "bzip2 compression logs and produces .xml.bz2 extension" {
    local output
    output=$(run_backup -e COMPRESSION=bzip2)
    echo "output: ${output}"
    [[ "${output}" == *"compressing backup with bzip2"* ]]
    [[ "${output}" == *".xml.bz2"* ]]
}

@test "bzip alias produces .xml.bz2 extension" {
    local output
    output=$(run_backup -e COMPRESSION=bzip)
    echo "output: ${output}"
    [[ "${output}" == *".xml.bz2"* ]]
}

@test "bzip3 compression logs and produces .xml.bz3 extension" {
    skip "bzip3 not available on Amazon Linux 2023"
}

@test "lzop compression logs and produces .xml.lzo extension" {
    local output
    output=$(run_backup -e COMPRESSION=lzop)
    echo "output: ${output}"
    [[ "${output}" == *"compressing backup with lzop"* ]]
    [[ "${output}" == *".xml.lzo"* ]]
}

@test "lzo alias produces .xml.lzo extension" {
    local output
    output=$(run_backup -e COMPRESSION=lzo)
    echo "output: ${output}"
    [[ "${output}" == *".xml.lzo"* ]]
}

@test "pigz compression logs and produces .xml.pgz extension" {
    local output
    output=$(run_backup -e COMPRESSION=pigz)
    echo "output: ${output}"
    [[ "${output}" == *"compressing backup with pigz"* ]]
    [[ "${output}" == *".xml.pgz"* ]]
}

@test "pixz compression logs and produces .xml.pxz extension" {
    skip "pixz not available on Amazon Linux 2023"
}

@test "zip compression logs and produces .xml.zip extension" {
    local output
    output=$(run_backup -e COMPRESSION=zip)
    echo "output: ${output}"
    [[ "${output}" == *"compressing backup with zip"* ]]
    [[ "${output}" == *".xml.zip"* ]]
}

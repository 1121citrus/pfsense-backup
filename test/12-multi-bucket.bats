#!/usr/bin/env bats
# test/12-multi-bucket.bats — test multi-bucket upload and --dryrun behavior.
#
# Covers: BUCKET_LIST env with multiple buckets, --bucket-list CLI flag,
# backup shim BUCKET env var, --dryrun flag passing through to aws s3 mv.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

setup() {
    WHEREAMI="${BATS_TEST_DIRNAME}"
    IMAGE="${IMAGE:-1121citrus/pfsense-backup:latest}"
    export WHEREAMI IMAGE

    # Run the backup shim (pfsense-backup via backup) with stdout+stderr merged.
    run_backup() {
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
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

    # Run pfsense-backup directly with CLI args.
    run_pfsense_backup_args() {
        local cmd_args=("$@")
        # shellcheck disable=SC2086
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -e PFSENSE_HOST=fake-host \
            -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
            -e PFSENSE_IDENTITY_PASSWORD=testpassword \
            -e COMPRESSION=none \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
            -v "${WHEREAMI}/fixtures/test-path.sh:/etc/profile.d/test-path.sh:ro" \
            "${IMAGE}" /usr/local/bin/pfsense-backup "${cmd_args[@]}" 2>&1
    }

    export -f run_backup
    export -f run_pfsense_backup_args
}

# ── BUCKET env var (not AWS_S3_BUCKET_NAME) ───────────────────────────────────

@test "BUCKET env var (without AWS_S3_BUCKET_NAME) triggers S3 upload" {
    local output
    output=$(run_backup -e BUCKET=env-bucket-test)
    echo "output: ${output}"
    [[ "${output}" == *"env-bucket-test"* ]]
    [[ "${output}" == *"aws s3 mv"* ]]
}

# ── Multi-bucket via BUCKET_LIST env ─────────────────────────────────────────

@test "BUCKET_LIST with two buckets uploads to both" {
    local output
    output=$(run_backup -e "BUCKET_LIST=bucket-alpha bucket-beta")
    echo "output: ${output}"
    [[ "${output}" == *"bucket-alpha"* ]]
    [[ "${output}" == *"bucket-beta"* ]]
}

@test "BUCKET_LIST with two buckets calls aws s3 mv twice" {
    local output count
    output=$(run_backup -e "BUCKET_LIST=bucket-alpha bucket-beta")
    echo "output: ${output}"
    # "running aws s3 mv" is logged once per bucket; count those lines.
    count=$(echo "${output}" | grep -c "running aws s3 mv" || true)
    [ "${count}" -eq 2 ]
}

# ── Multi-bucket via --bucket-list CLI flag ───────────────────────────────────

@test "--bucket-list CLI flag uploads to both buckets" {
    local output
    output=$(run_pfsense_backup_args --bucket-list "bucket-one bucket-two")
    echo "output: ${output}"
    [[ "${output}" == *"bucket-one"* ]]
    [[ "${output}" == *"bucket-two"* ]]
}

@test "--bucket-list calls aws s3 mv for each bucket" {
    local output count
    output=$(run_pfsense_backup_args --bucket-list "bucket-one bucket-two")
    echo "output: ${output}"
    # "running aws s3 mv" is logged once per bucket; count those lines.
    count=$(echo "${output}" | grep -c "running aws s3 mv" || true)
    [ "${count}" -eq 2 ]
}

# ── --dryrun flag ─────────────────────────────────────────────────────────────

@test "--dryrun passes --dryrun to aws s3 mv" {
    local output
    output=$(run_pfsense_backup_args --bucket dryrun-bucket --dryrun)
    echo "output: ${output}"
    [[ "${output}" == *"--dryrun"* ]]
}

@test "DRYRUN=true env passes --dryrun to aws s3 mv" {
    local output
    output=$(run_backup -e AWS_S3_BUCKET_NAME=dryrun-bucket -e DRYRUN=true)
    echo "output: ${output}"
    [[ "${output}" == *"--dryrun"* ]]
}

@test "--dryrun exits 0 (aws mock accepts dryrun flag)" {
    run run_pfsense_backup_args --bucket dryrun-bucket --dryrun
    [ "$status" -eq 0 ]
}

# ── backup shim: --bucket CLI flag ───────────────────────────────────────────

@test "backup shim accepts --bucket CLI flag" {
    local output
    output=$(
        docker run -i --rm ${DOCKER_RUN_ARGS:-} \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -e PFSENSE_HOST=fake-host \
            -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
            -e PFSENSE_IDENTITY_PASSWORD=testpassword \
            -e COMPRESSION=none \
            -v "${WHEREAMI}/bin:/test/bin:ro" \
            -v "${WHEREAMI}/fixtures:/test/fixtures:ro" \
            -v "${WHEREAMI}/fixtures/test-path.sh:/etc/profile.d/test-path.sh:ro" \
            "${IMAGE}" /usr/local/bin/backup --bucket shim-cli-bucket 2>&1
    )
    echo "output: ${output}"
    [[ "${output}" == *"shim-cli-bucket"* ]]
}

@test "backup shim exits non-zero when no bucket and no --bucket flag" {
    run run_backup \
        -e PFSENSE_HOST=fake-host \
        -e PFSENSE_IDENTITY_FILE=/test/fixtures/pfsense-identity.key \
        -e PFSENSE_IDENTITY_PASSWORD=testpassword
    [ "$status" -ne 0 ]
}

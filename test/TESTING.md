# Testing guide

## Overview

The test suite has two layers:

| Layer | Location | Requires live systems | Run in CI |
|---|---|---|---|
| Unit / integration | `test/backup-*`, `test/healthcheck` | No | Yes |
| Staging | `test/staging` | Yes — real pfSense, real AWS | No |

---

## Automated test suite

### Running the full suite

```bash
./test/run-all
```

Or via the build script (lint + build + test + scan):

```bash
./build
```

### Individual test files

```bash
./test/backup-required-vars    # required-variable validation
./test/backup-success          # successful backup, all compression modes
./test/backup-encryption       # GPG encryption paths
./test/backup-xml-validation   # XML field extraction and filename sanitization
./test/backup-aws-failure      # aws s3 mv failure detection and marker behavior
./test/healthcheck             # all healthcheck scenarios
```

### How the tests work

Each test file runs `docker run` against the image, binding `test/bin/` over
`/usr/local/bin` via `PATH` prepend.  Stub scripts in `test/bin/` replace
`ssh`, `sshpass`, `aws`, and `traceroute`, so no real network access or AWS
credentials are needed.

The `ssh` stub serves fixture XML from `test/fixtures/config.xml` (or a
different file when `SSH_FIXTURE_FILE` is set).  The `aws` stub prints its
arguments and exits 0 (or the code set in `AWS_EXIT_CODE`).

### `IMAGE` env var

Tests use the image named in `IMAGE`.  When invoked via `./build`, the
just-built image is passed automatically.  To run tests against a specific
image:

```bash
IMAGE=1121citrus/pfsense-backup:1.2.3 ./test/run-all
```

### CI

The automated suite runs in GitHub Actions on every push and pull request.
See `.github/workflows/ci.yml`.  Staging tests are excluded from CI because
they require live credentials and external systems.

---

## Staging tests (manual — requires live systems)

`test/staging` exercises the backup pipeline end-to-end against a real
pfSense host and a real AWS S3 bucket.  These tests are **not** run in CI
and require explicit setup and confirmation before they execute.

### Options

All parameters can be supplied as CLI flags or environment variables.
CLI flags take precedence over environment variables.

```text
test/staging [options] [IMAGE]
```

| Flag | Environment variable | Description |
|---|---|---|
| `IMAGE` (positional) | `IMAGE` | Image to test |
| `--image IMAGE` | `IMAGE` | Image to test (alternative to positional) |
| `--host HOST` | `PFSENSE_HOST` | pfSense hostname or IP |
| `--identity-file FILE` | `PFSENSE_IDENTITY_FILE` | SSH identity (private key) file |
| `--identity-password PASS` | `PFSENSE_IDENTITY_PASSWORD` | SSH key passphrase (or a readable file path, treated as `--identity-password-file`) |
| `--identity-password-file FILE` | `PFSENSE_IDENTITY_PASSWORD_FILE` | File containing the SSH key passphrase |
| `--compression FORMAT` | `COMPRESSION` | Backup compression format |
| `--bucket BUCKET` | `AWS_S3_BUCKET_NAME` | Target S3 bucket |
| `--aws-config FILE` | `AWS_CONFIG_FILE` | AWS CLI config file (alternative to inline key/secret) |
| `--dryrun` | `AWS_DRYRUN=true` | Enable S3 dry-run (no real writes) |
| `--no-dryrun` | `AWS_DRYRUN=false` | Disable S3 dry-run (write real objects) |
| `--yes` | — | Skip the interactive confirmation prompt |
| `--test TEST` | — | Run only the named test function |
| `-h, --help` | — | Print usage and exit |

Inline AWS credentials are also accepted via `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY` as an alternative to `--aws-config`.

### Bucket safety

If `--bucket` does not start with `test.` or `staging.`, a caution is
displayed and `--dryrun` is forced on.  To allow real writes to a
production bucket, pass `--no-dryrun` explicitly.

### Usage

```bash
# Minimal: image-only smoke tests (no credentials needed)
test/staging 1121citrus/pfsense-backup:dev-abc1234

# With live pfSense (pfSense-dependent tests enabled)
test/staging \
    --host 192.168.1.1 \
    --identity-file ~/.ssh/pfsense-identity \
    --identity-password-file ~/.secrets/pfsense-password \
    1121citrus/pfsense-backup:dev-abc1234

# Full end-to-end: pfSense + AWS (dryrun, safe)
test/staging \
    --host 192.168.1.1 \
    --identity-file ~/.ssh/pfsense-identity \
    --identity-password-file ~/.secrets/pfsense-password \
    --bucket staging.my-backups \
    --aws-config ~/.secrets/aws-config \
    1121citrus/pfsense-backup:dev-abc1234

# Full end-to-end: production bucket (real S3 writes)
test/staging \
    --host 192.168.1.1 \
    --identity-file ~/.ssh/pfsense-identity \
    --identity-password-file ~/.secrets/pfsense-password \
    --bucket my-real-backups \
    --aws-config ~/.secrets/aws-config \
    --no-dryrun \
    1121citrus/pfsense-backup:dev-abc1234

# Skip confirmation prompt (scripted / CI-adjacent use)
test/staging --yes \
    --host 192.168.1.1 \
    --identity-file ~/.ssh/pfsense-identity \
    --identity-password-file ~/.secrets/pfsense-password \
    --bucket staging.my-backups \
    1121citrus/pfsense-backup:dev-abc1234

# Run a single named test
test/staging --test test_staging_cron_fires \
    --host 192.168.1.1 \
    --identity-file ~/.ssh/pfsense-identity \
    --identity-password-file ~/.secrets/pfsense-password \
    --bucket staging.my-backups \
    1121citrus/pfsense-backup:dev-abc1234
```

### What the staging tests cover

| Test | Requires |
|---|---|
| `/usr/local/bin/backup` exists and is executable | Image only |
| `/usr/local/bin/pfsense-backup` exists and is executable | Image only |
| `startup` exists and is executable | Image only |
| `/usr/local/bin/healthcheck` exists and is executable | Image only |
| `sshpass` is present in the image | Image only |
| `ssh` is present in the image | Image only |
| `aws` CLI is present in the image | Image only |
| `backup` with missing `AWS_S3_BUCKET_NAME` exits non-zero | Image only |
| `backup` with missing `PFSENSE_HOST` exits non-zero | Image only |
| `backup` with missing identity file exits non-zero | Image only |
| `backup` with no credential exits non-zero | Image only |
| Downloads config XML from live pfSense | Live pfSense |
| Backup filename contains hostname and version from XML | Live pfSense |
| End-to-end backup completes (SSH + upload) | Live pfSense + AWS |
| Cron fires on schedule and backup completes | Live pfSense + AWS |

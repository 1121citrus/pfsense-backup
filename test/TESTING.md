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

### Required environment variables

| Variable | Description |
|---|---|
| `IMAGE` | Image to test (`./build` sets this; pass as `$1` to `test/staging`) |
| `PFSENSE_HOST` | Hostname or IP of the pfSense firewall |
| `PFSENSE_IDENTITY_FILE` | Path to the SSH identity (private key) file |
| `PFSENSE_IDENTITY_PASSWORD` | Passphrase for the identity file (or use `PFSENSE_IDENTITY_PASSWORD_FILE`) |
| `AWS_S3_BUCKET_NAME` | Target S3 bucket name |
| `AWS_CONFIG_FILE` | Path to AWS CLI config file (or set `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) |

### Optional environment variables

| Variable | Default | Description |
|---|---|---|
| `PFSENSE_USER` | `remote-backup` | SSH username on pfSense |
| `PFSENSE_IDENTITY_PASSWORD_FILE` | `/run/secrets/pfsense-identity-password` | File containing the key passphrase |
| `AWS_DRYRUN` | `true` (for non-test/staging buckets) | Pass `--dryrun` to `aws s3 mv` |
| `COMPRESSION` | `none` | Compression algorithm |
| `CRON_EXPRESSION` | `@daily` | Schedule for cron tests |

### Bucket safety

If `AWS_S3_BUCKET_NAME` does not start with `test.` or `staging.`, a strong
caution is displayed and `AWS_DRYRUN` is forced to `true`.  To allow real
writes to a production bucket, explicitly set `AWS_DRYRUN=false`.

### Usage

```bash
# Minimal: tests that do not require a live pfSense or AWS
IMAGE=1121citrus/pfsense-backup:dev-abc1234 ./test/staging

# With live pfSense (switch-dependent tests enabled)
PFSENSE_HOST=192.168.1.1 \
PFSENSE_IDENTITY_FILE=~/.ssh/pfsense-identity \
PFSENSE_IDENTITY_PASSWORD=secret \
IMAGE=1121citrus/pfsense-backup:dev-abc1234 \
./test/staging

# Full end-to-end: pfSense + AWS (dryrun, safe)
PFSENSE_HOST=192.168.1.1 \
PFSENSE_IDENTITY_FILE=~/.ssh/pfsense-identity \
PFSENSE_IDENTITY_PASSWORD=secret \
AWS_S3_BUCKET_NAME=staging.my-backups \
AWS_CONFIG_FILE=~/.aws/config \
IMAGE=1121citrus/pfsense-backup:dev-abc1234 \
./test/staging

# Full end-to-end: production bucket (requires AWS_DRYRUN=false)
PFSENSE_HOST=192.168.1.1 \
PFSENSE_IDENTITY_FILE=~/.ssh/pfsense-identity \
PFSENSE_IDENTITY_PASSWORD=secret \
AWS_S3_BUCKET_NAME=my-real-backups \
AWS_CONFIG_FILE=~/.aws/config \
AWS_DRYRUN=false \
IMAGE=1121citrus/pfsense-backup:dev-abc1234 \
./test/staging
```

### What the staging tests cover

| Test | Requires |
|---|---|
| Image has `/usr/local/bin/backup` | Image only |
| `backup --help` exits non-zero gracefully | Image only |
| `backup` with missing `AWS_S3_BUCKET_NAME` exits non-zero | Image only |
| `backup` with missing `PFSENSE_HOST` exits non-zero | Image only |
| `backup` with missing identity file exits non-zero | Image only |
| Download config from real pfSense | Live pfSense |
| Compress and upload to S3 (dryrun or real) | Live pfSense + AWS |
| Cron fires on schedule and completes backup | Live pfSense + AWS + service |

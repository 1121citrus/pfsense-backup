# Testing guide

## Overview

The test suite has two layers:

| Layer | Location | Requires live systems | Run in CI |
|---|---|---|---|
| Automated stubbed suites | `test/01-build.bats` through `test/12-multi-bucket.bats` | No | Yes |
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
# Suites that run in CI
bats test/01-build.bats
bats test/02-pfsense-backup.bats
bats test/03-backup-required-vars.bats
bats test/04-backup-success.bats
bats test/05-backup-encryption.bats
bats test/06-backup-aws-failure.bats
bats test/07-backup-xml-validation.bats
bats test/08-healthcheck.bats
bats test/09-image-metadata.bats
bats test/10-pfsense-backup-cli-flags.bats
bats test/11-scheduler-mode.bats
bats test/12-multi-bucket.bats
```

### How the tests work

Each `.bats` file runs `docker run` against the image, binding `test/bin/` over
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
See `.github/workflows/ci.yml`. Staging tests are excluded from CI because
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
| `--user USER` | `PFSENSE_USER` | SSH username (default: `remote-backup`) |
| `--identity-file FILE` | `PFSENSE_IDENTITY_FILE` | SSH identity (private key) file |
| `--identity-password PASS` | `PFSENSE_IDENTITY_PASSWORD` | SSH key passphrase (or a readable file path, treated as `--identity-password-file`) |
| `--identity-password-file FILE` | `PFSENSE_IDENTITY_PASSWORD_FILE` | File containing the SSH key passphrase |
| `--compression FORMAT` | `COMPRESSION` | Backup compression format |
| `--bucket BUCKET` | `AWS_S3_BUCKET_NAME` | Target S3 bucket |
| `--aws-config FILE` | `AWS_CONFIG_FILE` | AWS CLI config file (alternative to inline key/secret) |
| `--dryrun` | `DRYRUN=true` | Enable S3 dry-run (no real writes) |
| `--no-dryrun` | `DRYRUN=false` | Disable S3 dry-run (write real objects) |
| `--scan` | `STAGING_SCAN=true` | Run Trivy scan (default) |
| `--no-scan` | `STAGING_SCAN=false` | Skip Trivy scan; implies `--no-advise` unless `--advise` is set |
| `--advise [LIST]` | `STAGING_ADVISE=true` | Run advisory scans (`grype`, `scout`, `dive`, `all`) |
| `--no-advise` | `STAGING_ADVISE=false` | Disable advisory scans |
| `--yes` | — | Skip the interactive confirmation prompt |
| `--test TEST` | — | Run only the named test function |
| `-h, --help` | — | Print usage and exit |

Inline AWS credentials are also accepted via `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY` as an alternative to `--aws-config`.

### Dive layer analysis (`.dive-ci`)

When `--advise dive` (or `--advise all`) is passed, the image is analyzed by
[Dive](https://github.com/wagoodman/dive) in CI mode (`--ci`).  Dive reads
pass/fail thresholds from `.dive-ci` at the project root.  Without a config
file, Dive falls back to its built-in defaults, which are too strict for
this image.

#### Threshold choices

| Rule | Dive default | This project | Reason |
|---|---|---|---|
| `lowestEfficiency` | 0.9 | 0.9 | Kept at default — no change needed |
| `highestWastedBytes` | 20 MB | disabled | Absolute byte count is unpredictable across Alpine releases; see below |
| `highestUserWastedPercent` | 10% (0.1) | 20% (0.2) | `apk upgrade` creates inherent waste; see below |

**`highestWastedBytes: disabled`**

The `Dockerfile` runs `apk upgrade` to pull security fixes into the
`alpine:3.21` base layer.  Upgraded packages shadow the copies that shipped
in the base image; Dive counts those originals as wasted bytes because they
are still present in the base layer but inaccessible.  The exact byte count
varies with each Alpine point release (which changes what is pre-installed),
so a fixed byte limit would cause spurious failures on routine base-image
bumps.  Disabling the rule sidesteps that brittleness while `highestUserWastedPercent`
still provides a percentage-based safety net.

**`highestUserWastedPercent: 0.20`**

The default 0.10 (10%) is too tight for Alpine images that run `apk upgrade`.
The upgrade step replaces base-image files in the user layer, and the resulting
waste fraction depends on how many packages were upgraded.  0.20 (20%) provides
a buffer large enough to absorb expected upgrade waste while still catching
genuinely bloated images such as accidentally committed caches or unnecessary
tool installations.

#### Config file mechanics

`.dive-ci` lives at the project root alongside the `Dockerfile`.  When Dive
is invoked from `build` or `test/staging`, the file is mounted read-only into
the Dive container (`-v …/.dive-ci:/.dive-ci:ro`) and loaded via
`--ci-config /.dive-ci`.  If the file is absent, Dive uses its built-in
defaults.

---

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
| Healthcheck exits 0 when crontab configured, supercronic running, and fresh backup marker present | Image only |
| Healthcheck exits non-zero when crontab is missing | Image only |
| Healthcheck exits non-zero when supercronic is not running | Image only |
| Healthcheck exits 0 within startup grace period (no backup yet) | Image only |
| Healthcheck exits non-zero when backup marker is too old | Image only |
| Downloads config XML from live pfSense | Live pfSense |
| Backup filename contains hostname and version from XML | Live pfSense |
| End-to-end backup completes (SSH + upload) | Live pfSense + AWS |
| Cron fires on schedule and backup completes | Live pfSense + AWS |

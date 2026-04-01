# test — pfsense-backup test suite

For detailed test documentation see **[TESTING.md](TESTING.md)**.

## Quick start

```sh
# Run the full automated suite via the build script:
./build --no-scan

# Run the automated suite directly:
IMAGE=1121citrus/pfsense-backup:dev-abc1234 ./test/run-all

# Run one suite locally when bats is installed:
bats test/04-backup-success.bats

# Pre-release staging (requires live pfSense + credentials):
./test/staging \
    --host 192.168.1.1 \
    --identity-file ~/.ssh/pfsense-identity \
    --identity-password-file ~/.secrets/pfsense-password \
    1121citrus/pfsense-backup:dev-abc1234
```

## Structure

| Path | Purpose |
| --- | --- |
| `run-all` | Runner — executes all automated tests |
| `01-build.bats` | Image build assertions |
| `02-pfsense-backup.bats` | Core CLI backup flow |
| `03-backup-required-vars.bats` | Required-variable validation |
| `04-backup-success.bats` | Successful backup, all compression modes |
| `05-backup-encryption.bats` | GPG encryption paths |
| `06-backup-aws-failure.bats` | AWS failure detection and marker behaviour |
| `07-backup-xml-validation.bats` | XML field extraction and filename sanitisation |
| `08-healthcheck.bats` | Container health check scenarios |
| `09-image-metadata.bats` | OCI metadata and image annotation checks |
| `10-pfsense-backup-cli-flags.bats` | Additional CLI flag coverage |
| `11-scheduler-mode.bats` | Scheduler-mode entry and validation coverage |
| `12-multi-bucket.bats` | Multi-bucket upload and dry-run coverage |
| `staging` | Manual pre-release end-to-end tests (live pfSense) |
| `bin/` | Test stubs (`ssh`, `sshpass`, `aws`, `traceroute`) |
| `fixtures/` | Static XML fixture data |
| `TESTING.md` | Full test documentation |

GitHub Actions currently runs suites `01` through `12` in a single CI job.

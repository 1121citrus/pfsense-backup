# test — pfsense-backup test suite

For detailed test documentation see **[TESTING.md](TESTING.md)**.

## Quick start

```sh
# Run the full automated suite via the build script:
./build --no-scan

# Run the automated suite directly:
IMAGE=1121citrus/pfsense-backup:dev-abc1234 test/run-all

# Pre-release staging (requires live pfSense + credentials):
test/staging \
    --host 192.168.1.1 \
    --identity-file ~/.ssh/pfsense-identity \
    --identity-password-file ~/.secrets/pfsense-password \
    1121citrus/pfsense-backup:dev-abc1234
```

## Structure

| Path | Purpose |
| --- | --- |
| `run-all` | Runner — executes all automated tests |
| `backup-required-vars` | Required-variable validation |
| `backup-success` | Successful backup, all compression modes |
| `backup-encryption` | GPG encryption paths |
| `backup-xml-validation` | XML field extraction and filename sanitisation |
| `backup-aws-failure` | AWS failure detection and marker behaviour |
| `healthcheck` | Container health check scenarios |
| `build-options` | `build` and `staging` script option parsing |
| `pfsense-backup` | Additional CLI tests |
| `staging` | Manual pre-release end-to-end tests (live pfSense) |
| `bin/` | Test stubs (`ssh`, `sshpass`, `aws`, `traceroute`) |
| `fixtures/` | Static XML fixture data |
| `TESTING.md` | Full test documentation |

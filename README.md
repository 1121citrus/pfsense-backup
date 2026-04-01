# 1121citrus/pfsense-backup

An application specific service to create [pfSense](https://docs.netgate.com/pfsense/en/latest/) backups and copy them to S3.

## Contents

- [Contents](#contents)
- [Synopsis](#synopsis)
- [Overview](#overview)
- [Example: one-shot download (CLI)](#example-one-shot-download-cli)
- [Example: one-shot backup to S3](#example-one-shot-backup-to-s3)
- [Example: backup periodically as cron job](#example-backup-periodically-as-cron-job)
  - [Example log output](#example-log-output)
- [Example: Docker compose file](#example-docker-compose-file)
- [Configuration](#configuration)
- [Health check](#health-check)
- [Security](#security)
- [Building](#building)
- [Testing](#testing)
- [Attributions and provenance](#attributions-and-provenance)

## Synopsis

- Download the [pfSense](https://docs.netgate.com/pfsense/en/latest/) router configuration directly to stdout.
- Periodically backup the configuration to off-site storage (S3).
- Backup files are renamed so they sort by date.
- Credentials are supplied by a compose
[secret](https://docs.docker.com/compose/how-tos/use-secrets/).

## Overview

The primary use case is `pfsense-backup` as a CLI: run it directly and
redirect stdout to a file.  For S3 uploads, use `pfsense-backup` with
`--bucket` or `--bucket-list` for one-shot runs, or `pfsense-backup --cron`
for scheduled runs backed by `supercronic`.

The image `CMD` is `/usr/local/bin/backup`, which preserves the older
single-shot S3-upload behavior.  The `backup` and `startup` scripts are
compatibility shims; new deployments should call `pfsense-backup` directly.

You must separately provision and deploy:

1. An SSH key pair. It is recommended that the key pair be created that is
specific to the remote backup task.
2. A user is created on the pfSense system that will be used to copy the
configuration file. The default name is 'remote-backup'.
    1. Grant the user `User - System: Shell account access` privilege
    2. Set the public key as an authorized key for the user and **restrict
    it to only copying the config file** (see [Security](#security)).

  ```console
  $ cat /home/remote-backup/.ssh/authorized_keys
  restrict,pty,command="cat /cf/conf/config.xml" ssh-ed25519 AAAAC3NzaC1lQDI1MTE5AAAAIFcn7Vhwxi8rQw0/Aw7pMFfD9h6zOzDXUd/insHpcQ2o remote-backup
  ```

## Example: one-shot download (CLI)

Download the pfSense configuration directly to a file:

```console
$ docker run --rm \
      -e PFSENSE_HOST=firewall \
      -v ~/.ssh/firewall-remote-backup.ed25519:/run/secrets/pfsense-identity:ro \
      -v ./secrets/pfsense-identity-password:/run/secrets/pfsense-identity-password:ro \
      1121citrus/pfsense-backup pfsense-backup > config.xml
[INFO] 20260316T163601 pfsense-backup begin pfsense-backup
[INFO] 20260316T163604 pfsense-backup downloaded '20260316T163604-firewall-pfsense-v24.11-config-backup.xml' to '/tmp/tmp.abc1/20260316T163604-firewall-pfsense-v24.11-config-backup.xml'
[INFO] 20260316T163604 pfsense-backup backup '20260316T163604-firewall-pfsense-v24.11-config-backup.xml': writing '/tmp/tmp.abc1/20260316T163604-firewall-pfsense-v24.11-config-backup.xml' to stdout
[INFO] 20260316T163604 pfsense-backup finish pfsense-backup
```

Use `pfsense-backup --help` to see all available options:

```console
$ docker run --rm 1121citrus/pfsense-backup pfsense-backup --help
Usage: pfsense-backup [options]

Download a pfSense firewall configuration to stdout.

Options:
  -?,--help              Display this help text
  -v,--version           Display command version
  -H,--host HOST         pfSense hostname or IP
  ...
```

## Example: one-shot backup to S3

Add the `backup` command to run a single backup directly to S3:

```console
$ docker run -i --rm \
      -e AWS_S3_BUCKET_NAME=backups-bucket \
      -e PFSENSE_HOST=firewall \
      -v ./secrets/aws-config:/run/secrets/aws-config:ro \
      -v ~/.ssh/firewall-remote-backup.ed25519:/run/secrets/pfsense-identity:ro \
      -v ./secrets/pfsense-identity-password:/run/secrets/pfsense-identity-password:ro \
      -v /etc/localtime:/etc/localtime:ro \
      1121citrus/pfsense-backup backup
[INFO] 20260315T013601 pfsense-backup begin firewall 'firewall' backup to 'backups-bucket' bucket
[INFO] 20260315T013601 pfsense-backup begin backup
[INFO] 20260315T013604 pfsense-backup downloaded '20260315T013604-firewall-pfsense-v24.0-config-backup.xml' to '/tmp/tmp.abc1/20260315T013604-firewall-pfsense-v24.0-config-backup.xml'
[INFO] 20260315T013604 pfsense-backup begin mv '/tmp/tmp.abc1/20260315T013604-firewall-pfsense-v24.0-config-backup.xml' to S3 bucket 'backups-bucket'
[INFO] 20260315T013606 pfsense-backup running aws s3 mv --no-progress /tmp/tmp.abc1/20260315T013604-firewall-pfsense-v24.0-config-backup.xml s3://backups-bucket/20260315T013604-firewall-pfsense-v24.0-config-backup.xml
[INFO] 20260315T013606 pfsense-backup move: /tmp/tmp.abc1/20260315T013604-firewall-pfsense-v24.0-config-backup.xml to s3://backups-bucket/20260315T013604-firewall-pfsense-v24.0-config-backup.xml
[INFO] 20260315T013606 pfsense-backup completed aws s3 mv --no-progress /tmp/tmp.abc1/20260315T013604-firewall-pfsense-v24.0-config-backup.xml s3://backups-bucket/20260315T013604-firewall-pfsense-v24.0-config-backup.xml
[INFO] 20260315T013606 pfsense-backup finish backup
[INFO] 20260315T013606 pfsense-backup completed firewall 'firewall' backup to 'backups-bucket' bucket
```

## Example: backup periodically as scheduler service

Run `pfsense-backup --cron` to enter scheduler mode:

```console
$ docker run -i --rm \
  -e BUCKET=backups-bucket \
      -e CRON_EXPRESSION='*/15 * * * *' \
      -e PFSENSE_HOST=firewall \
      -v ./secrets/aws-config:/run/secrets/aws-config:ro \
      -v ./secrets/remote-backup-identity.ed25519:/run/secrets/pfsense-identity:ro \
      -v ./secrets/pfsense-identity-password:/run/secrets/pfsense-identity-password:ro \
      -v /etc/localtime:/etc/localtime:ro \
  1121citrus/pfsense-backup /usr/local/bin/pfsense-backup --cron
```

Existing deployments that still set `entrypoint: /usr/local/bin/startup`
continue to work because `startup` now execs `pfsense-backup --cron`.

### Example log output

```console
[INFO] 20260316T163325 pfsense-backup entering scheduler mode (*/15 * * * *)
[INFO] 20260316T163325 pfsense-backup wrote env file /pfsense-backup/.env
[INFO] 20260316T163325 pfsense-backup export AWS_CONFIG_FILE=/run/secrets/aws-config
[INFO] 20260316T163325 pfsense-backup export BUCKET=backups-bucket
[INFO] 20260316T163325 pfsense-backup export BUCKET_LIST=backups-bucket
[INFO] 20260316T163325 pfsense-backup unset CRON_EXPRESSION
[INFO] 20260316T163325 pfsense-backup export PFSENSE_HOST=firewall
[INFO] 20260316T163325 pfsense-backup installing cron entry: */15 * * * * /usr/local/bin/pfsense-backup
[INFO] 20260316T163325 pfsense-backup crontab: SHELL=/bin/sh
[INFO] 20260316T163325 pfsense-backup handing off to supercronic
   .
   .
   .
[INFO] 20260316T164500 pfsense-backup begin firewall 'firewall' backup to 'backups-bucket' bucket
[INFO] 20260316T164500 pfsense-backup begin pfsense-backup
[INFO] 20260316T164502 pfsense-backup compressing backup with lzma/xz --compress --extreme --quiet: /tmp/tmp.123/config.xml.xz
[INFO] 20260316T164502 pfsense-backup encrypting backup with GPG
[INFO] 20260316T164503 pfsense-backup downloaded '20260316T164502-firewall-1-pfsense-v24.0-config-backup.xml' to '/tmp/tmp.123/20260316T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg'
[INFO] 20260316T164503 pfsense-backup begin mv '/tmp/tmp.123/20260316T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg' to S3 bucket 'backups-bucket'
[INFO] 20260316T164503 pfsense-backup running aws s3 mv --no-progress /tmp/tmp.123/20260316T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg s3://backups-bucket/20260316T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg
[INFO] 20260316T164504 pfsense-backup move: /tmp/tmp.123/20260316T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg to s3://backups-bucket/20260316T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg
[INFO] 20260316T164504 pfsense-backup completed aws s3 mv --no-progress /tmp/tmp.123/20260316T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg s3://backups-bucket/20260316T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg
[INFO] 20260316T164504 pfsense-backup finish pfsense-backup
[INFO] 20260316T164504 pfsense-backup completed firewall 'firewall' backup to 'backups-bucket' bucket
```

## Example: Docker compose file

```yml
services:
  pfsense-backup:
    container_name: pfsense-backup
    image: 1121citrus/pfsense-backup:latest
    restart: always
    command: ["/usr/local/bin/pfsense-backup", "--cron"]
    environment:
      - BUCKET=${BUCKET:-backup-bucket}
      - CRON_EXPRESSION=${CRON_EXPRESSION:-15 3 * * *}
      - PFSENSE_HOST=firewall
      - TZ=${TZ:-US/Eastern}
    volumes:
      - /etc/localtime:/etc/localtime:ro
    secrets:
      - aws-config
      - pfsense-identity
      - pfsense-identity-password

secrets:
  aws-config:
    file: ./aws-config
  pfsense-identity:
    file: ./pfsense-identity
  pfsense-identity-password:
    file: ./pfsense-identity-password
```

## Configuration

### `pfsense-backup` CLI options

Option | Env var | Default | Notes
--- | --- | --- | ---
`-H,--host HOST` | `PFSENSE_HOST` | _(see notes)_ | pfSense hostname or IP. Falls back to `TAILSCALE_HOST`, then first-hop gateway from `traceroute`.
`-u,--user USER` | `PFSENSE_USER` | `remote-backup` | SSH username.
`-i,--identity-file FILE` | `PFSENSE_IDENTITY_FILE` | `/run/secrets/pfsense-identity` | Private key file.
`-p,--password PW` | `PFSENSE_IDENTITY_PASSWORD` | _(none)_ | Key passphrase. **WARNING: visible in process table — prefer `--password-file`.**
`-P,--password-file FILE` | `PFSENSE_IDENTITY_PASSWORD_FILE` | `/run/secrets/pfsense-identity-password` | File containing the key passphrase.
`--strict-host-key-checking MODE` | `PFSENSE_SSH_STRICT_HOST_KEY_CHECKING` | `accept-new` | SSH host-key checking mode (`yes`, `accept-new`, `no`).
`--known-hosts FILE` | `PFSENSE_SSH_KNOWN_HOSTS_FILE` | `${HOME}/.ssh/known_hosts` | Known hosts file.
`-b,--bucket BUCKET` | `BUCKET` | `AWS_S3_BUCKET_NAME` fallback | Upload one backup to one S3 bucket. `AWS_S3_BUCKET_NAME` is a legacy single-bucket alias.
`--bucket-list 'B1 B2'` | `BUCKET_LIST` | _(none)_ | Upload the same backup to multiple buckets. Values are bucket names only, not `bucket/prefix` paths.
`--dryrun` / `--no-dryrun` | `DRYRUN` | `false` | Pass `--dryrun` to `aws s3 mv`. `--dryrun` skips the interactive confirmation gate.
`-y,--yes` | `YES` | `false` | Skip the interactive confirmation prompt for live uploads.
`--aws-config FILE` | `AWS_CONFIG_FILE` | `/run/secrets/aws-config` | AWS CLI config/credentials file.
`--aws-extra-args ARGS` | `AWS_EXTRA_ARGS` | _(none)_ | Extra arguments appended to AWS CLI calls.
`--compression FORMAT` | `COMPRESSION` | `none` | Compression mode: `bzip`, `bzip2`, `bzip3`, `gz`, `gzip`, `lzma`, `lzo`, `lzop`, `none`, `pigz`, `pixz`, `xz`, `zip`.
`--gpg-cipher-algo ALGO` | `GPG_CIPHER_ALGO` | `aes256` | Cipher used for optional symmetric GPG encryption.
`--gpg-passphrase PASS` | `GPG_PASSPHRASE` | _(none)_ | GPG passphrase. **WARNING: visible in process table — prefer `--gpg-passphrase-file`.**
`--gpg-passphrase-file FILE` | `GPG_PASSPHRASE_FILE` | `/run/secrets/gpg-passphrase` | File containing the GPG passphrase.
`-c,--cron` | `CRON_EXPRESSION` | `@daily` | Enter scheduler mode and run on the current `CRON_EXPRESSION` value.
`--cron-expression EXPR` | `CRON_EXPRESSION` | `@daily` | Set the schedule and enter scheduler mode.
`--hourly N` | `HOURLY` | `24` | Retention policy knob. Also enters scheduler mode.
`--daily N` | `DAILY` | `7` | Retention policy knob. Also enters scheduler mode.
`--weekly N` | `WEEKLY` | `4` | Retention policy knob. Also enters scheduler mode.
`--monthly N` | `MONTHLY` | `6` | Retention policy knob. Also enters scheduler mode.
`--yearly N` | `YEARLY` | `always` | Retention policy knob. Also enters scheduler mode.

### Scheduler, upload, and healthcheck environment variables

Variable | Default | Notes
--- | --- | ---
`AWS_CONFIG_FILE` | `/run/secrets/aws-config` | The externally provided AWS configuration file containing credentials, etc. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`AWS_S3_BUCKET_NAME` | _(none)_ | Legacy single-bucket alias. New deployments should use `BUCKET` or `BUCKET_LIST`.
`BUCKET` | _(none)_ | Canonical single-bucket setting for one-shot uploads and scheduler mode.
`BUCKET_LIST` | _(none)_ | Space-separated list of bucket names for multi-bucket upload.
`COMPRESSION` | `none` | Compression application to apply: `bzip`, `bzip2`, `bzip3`, `gz`, `gzip`, `lzma`, `lzo`, `lzop`, `none`, `pigz`, `pixz`, `xz`, `zip`
`CRON_EXPRESSION` | `@daily` | Schedule used by `--cron` / scheduler mode. See [crontab.guru](https://crontab.guru/) for examples.
`DAILY` | `7` | Retention policy knob written into the scheduler environment.
`DEBUG` | `false` | Set to `true` to enable `xtrace` and `verbose` shell options, and `--verbose` option for `sshpass` and `ssh` client. **WARNING: enables credential exposure in logs — never use in production.**
`DRYRUN` | `false` | Canonical dry-run control for S3 uploads.
`GPG_CIPHER_ALGO` | `aes256` | GnuPG symmetric encryption cipher to use to encrypt the backup.
`GPG_PASSPHRASE` | _none_ | GnuPG symmetric encryption pass-phrase to use to encrypt the backup.  **WARNING: consider using the more secure `GPG_PASSPHRASE_FILE`**, which might be a bind mount or a compose secret.
`GPG_PASSPHRASE_FILE` | `/run/secrets/gpg-passphrase` | A file containing the symmetric encryption pass-phrase to use to encrypt the backup. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`HEALTHCHECK_MAX_AGE_SECONDS` | `172800` | Maximum allowed age in seconds of the latest successful backup marker before healthcheck fails. Default is 48 hours.
`HEALTHCHECK_STARTUP_FILE` | `/tmp/pfsense-backup.started-at` | File touched when scheduler mode starts, used by healthcheck grace-period logic.
`HEALTHCHECK_STARTUP_GRACE_SECONDS` | `900` | Grace period in seconds after container start before requiring a successful backup marker. Default is 15 minutes.
`HEALTHCHECK_SUCCESS_FILE` | `/tmp/pfsense-backup.last-success` | File touched when backup successfully uploads to S3, used by healthcheck recency validation.
`HOURLY` | `24` | Retention policy knob written into the scheduler environment.
`MONTHLY` | `6` | Retention policy knob written into the scheduler environment.
`PFSENSE_EXTRA_SSH_ARGS` | _none_ | Additional options to add to the `ssh` command.
`PFSENSE_EXTRA_SSHPASS_ARGS` | _none_ | Additional options to add to the `sshpass` command.
`TAILSCALE_HOST` | _none_ | Specify the hostname or IP address of the pfSense firewall on the Tailscale mesh. Do not include the final `/`, otherwise backup will fail. Used only when `PFSENSE_HOST` is unset.
`TZ` | `UTC` | Which timezone should `cron` use, e.g. `America/New_York` or `Europe/Warsaw`. See [full list of available time zones](http://manpages.ubuntu.com/manpages/bionic/man3/DateTime::TimeZone::Catalog.3pm.html).
`WEEKLY` | `4` | Retention policy knob written into the scheduler environment.
`YEARLY` | `always` | Retention policy knob written into the scheduler environment.
`YES` | `false` | Skip the interactive confirmation prompt for live uploads.

## Health check

The container exposes a Docker `HEALTHCHECK` that validates three things every
60 seconds when the container is running in scheduler mode:

1. **Crontab** — the supercronic schedule file is configured with the backup command.
2. **supercronic** — the scheduler process is running.
3. **Backup recency** — a recent successful backup marker exists.

Recency logic:

- If `HEALTHCHECK_SUCCESS_FILE` exists and its modification time is within
  `HEALTHCHECK_MAX_AGE_SECONDS` → **healthy**.
- If the success file is absent or stale, but `HEALTHCHECK_STARTUP_FILE`
  exists and the container has been running for less than
  `HEALTHCHECK_STARTUP_GRACE_SECONDS` → **healthy** (startup grace window).
- Otherwise → **unhealthy**.

The grace window correctly handles container restarts: if a stale success
marker survives on a persistent volume, the container is still considered
healthy during the startup grace period while waiting for the first new backup
to complete.

## Security

See [SECURITY.md](SECURITY.md) for the full security model, hardening
checklist, and vulnerability reporting instructions.

Key points:

- **Restrict the SSH key on pfSense** — use `restrict,command=...` in
  `authorized_keys` so the key can only read the config file.
- **Use Docker secrets** (file mounts) rather than environment variables for
  all credentials.
- **Use `--strict-host-key-checking yes`** (or `PFSENSE_SSH_STRICT_HOST_KEY_CHECKING=yes`)
  with a pre-populated known-hosts file for production deployments.
- **Never set `DEBUG=true` in production** — shell trace mode exposes
  credentials in container logs.

## Building

Use the `build` script to produce a multi-platform image:

```console
# Build for all platforms (linux/amd64 + linux/arm64), load locally
./build

# Build and push to Docker Hub with a version tag
./build --push --version 1.2.3

# Single-architecture local build
./build --platform linux/amd64
```

The script wraps `docker buildx build` and documents every flag in its source.
See `./build --help` for usage.

When `--push` is used, SBOM and SLSA provenance (`mode=max`) attestations are
embedded in the pushed multi-arch manifest automatically.

## Testing

Tests require a built Docker image tagged `1121citrus/pfsense-backup:latest`.

```console
# Run the full test suite
./test/run-all

# Run individual suites with bats installed locally
bats test/02-pfsense-backup.bats
bats test/04-backup-success.bats
bats test/05-backup-encryption.bats
bats test/07-backup-xml-validation.bats
bats test/08-healthcheck.bats
bats test/11-scheduler-mode.bats
bats test/12-multi-bucket.bats

# Test against a specific image tag
IMAGE=1121citrus/pfsense-backup:1.2.3 ./test/run-all
```

Tests use lightweight stub binaries in `test/bin/` that shadow the real
`ssh`, `sshpass`, `aws`, and `traceroute` commands inside the container.

GitHub Actions currently runs suites `01` through `12` in a single CI job.

## Attributions and provenance

Component | Source | License
--- | --- | ---
Alpine Linux base image | [hub.docker.com/_/alpine](https://hub.docker.com/_/alpine) | MIT / various
aws-cli | [github.com/aws/aws-cli](https://github.com/aws/aws-cli) | Apache-2.0
GnuPG | [gnupg.org](https://gnupg.org) | GPL-2.0
OpenSSH | [openssh.com](https://www.openssh.com) | BSD-style
sshpass | [sourceforge.net/projects/sshpass](https://sourceforge.net/projects/sshpass/) | GPL-2.0
pigz | [zlib.net/pigz](https://zlib.net/pigz/) | MIT / zlib
pixz | [github.com/vasi/pixz](https://github.com/vasi/pixz) | BSD-2-Clause

Multi-platform images pushed to Docker Hub include a Software Bill of
Materials (SBOM) and SLSA Build Level 3 provenance attestation. Inspect them
with:

```console
docker buildx imagetools inspect 1121citrus/pfsense-backup:latest \
  --format '{{ json .Provenance }}'
```

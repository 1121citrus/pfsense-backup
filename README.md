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
redirect stdout to a file.  Backup to S3 on a schedule is supported via
the legacy `backup` service wrapper and `startup` entrypoint.

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
  restrict,pty,command="cat /cf/conf/config.xml" ssh-ed25519 AAAAC3NzaC1lZDI1MTE5AAAAIFcn7Vcaxi8rQw0/Aw7ZMFfD9h6vOzTXUd/insHick2o remote-backup
  ```

## Example: one-shot download (CLI)

Download the pfSense configuration directly to a file:

```console
$ docker run --rm \
      -e PFSENSE_HOST=firewall \
      -v ~/.ssh/firewall-remote-backup.ed25519:/run/secrets/pfsense-identity:ro \
      -v ./secrets/pfsense-identity-password:/run/secrets/pfsense-identity-password:ro \
      1121citrus/pfsense-backup pfsense-backup > config.xml
[INFO] 20250916T163601 pfsense-backup begin pfsense-backup
[INFO] 20250916T163604 pfsense-backup streaming config: 20250916T163604-firewall-pfsense-v24.11-config-backup.xml
[INFO] 20250916T163604 pfsense-backup finish pfsense-backup
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
[INFO] 20250915T013601 backup begin backup
[INFO] 20250915T013601 pfsense-backup begin pfsense-backup
[INFO] 20250915T013604 pfsense-backup streaming config: 20250915T013604-firewall-pfsense-v24.0-config-backup.xml
[INFO] 20250915T013604 pfsense-backup finish pfsense-backup
[INFO] 20250915T013604 backup downloaded '20250915T013604-firewall-pfsense-v24.0-config-backup.xml'
[INFO] 20250915T013604 backup begin mv '20250915T013604-firewall-pfsense-v24.0-config-backup.xml' to S3 bucket 'backups-bucket'
[INFO] 20250915T013606 backup move: ./20250915T013604-firewall-pfsense-v24.0-config-backup.xml to s3://backups-bucket/20250915T013604-firewall-pfsense-v24.0-config-backup.xml
[INFO] 20250915T013606 backup completed aws s3 mv ...
[INFO] 20250915T013606 backup finish backup
```

## Example: backup periodically as cron job

Run without a command to start the service (cron) mode:

```console
$ docker run -i --rm \
      -e AWS_S3_BUCKET_NAME=backups-bucket \
      -e CRON_EXPRESSION='*/15 * * * *' \
      -e PFSENSE_HOST=firewall \
      -v ./secrets/aws-config:/run/secrets/aws-config:ro \
      -v ./secrets/remote-backup-identity.ed25519:/run/secrets/pfsense-identity:ro \
      -v ./secrets/pfsense-identity-password:/run/secrets/pfsense-identity-password:ro \
      -v /etc/localtime:/etc/localtime:ro \
      1121citrus/pfsense-backup
```

### Example log output

```console
[INFO] 20250916T163325 startup create env file /root/.env
[INFO] 20250916T163325 startup mode of '/root/.env' changed from 0644 (rw-r--r--) to 0600 (rw-------)
[INFO] 20250916T163325 startup export AWS_CONFIG_FILE='/run/secrets/aws-config'
[INFO] 20250916T163325 startup export AWS_DRYRUN='false'
[INFO] 20250916T163325 startup export AWS_S3_BUCKET_NAME='backups-bucket'
[INFO] 20250916T163325 startup export CRON_EXPRESSION='*/15 * * * *'
[INFO] 20250916T163325 startup export DEBUG='false'
[INFO] 20250916T163325 startup export GPG_CIPHER_ALGO='aes256'
[INFO] 20250916T163325 startup export GPG_PASSPHRASE='**REDACTED**'
[INFO] 20250916T163325 startup export GPG_PASSPHRASE_FILE='/run/secrets/gpg-passphrase'
[INFO] 20250916T163325 startup export PFSENSE_HOST='firewall'
[INFO] 20250916T163325 startup export PFSENSE_USER=''
[INFO] 20250916T163325 startup export PFSENSE_IDENTITY_FILE='/run/secrets/pfsense-identity'
[INFO] 20250916T163325 startup export PFSENSE_IDENTITY_PASSWORD='**REDACTED**'
[INFO] 20250916T163325 startup export PFSENSE_IDENTITY_PASSWORD_FILE='/run/secrets/pfsense-identity-password'
[INFO] 20250916T163325 startup export RSA_PUBLIC_KEY_FILE='/run/secrets/rsa-public-key'
[INFO] 20250916T163325 startup export TAILSCALE_HOST='100.76.132.97'
[INFO] 20250916T163325 startup installing cron.d entry: /usr/local/bin/backup
[INFO] 20250916T163325 startup mode of '/var/spool/cron/crontabs/root' changed from 0600 (rw-------) to 0644 (rw-r--r--)
[INFO] 20250916T163325 startup crontab: */15 * * * * /usr/local/bin/backup 2>&1
[INFO] 20250916T163325 startup handing the reins over to cron daemon
   .
   .
   .
[INFO] 20250916T164500 backup begin backup
[INFO] 20250916T164500 pfsense-backup begin pfsense-backup
[INFO] 20250916T164502 pfsense-backup streaming config: 20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml
[INFO] 20250916T164502 pfsense-backup finish pfsense-backup
[INFO] 20250916T164502 backup compressing backup with lzma/xz --compress --extreme --quiet: 20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz
[INFO] 20250916T164502 backup encrypting backup with GPG
[INFO] 20250916T164503 backup downloaded '20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml' to '20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg'
[INFO] 20250916T164503 backup begin mv '20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg' to S3 bucket 'backups-bucket'
[INFO] 20250916T164503 backup running aws s3 mv --no-progress 20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg s3://backups-bucket/20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg
[INFO] 20250916T164504 backup move: ./20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg to s3://backups-bucket/20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg
[INFO] 20250916T164504 backup completed aws s3 mv --no-progress ...
[INFO] 20250916T164504 backup finish backup
```

## Example: Docker compose file

```yml
services:
  pfsense-backup:
    container_name: pfsense-backup
    image: 1121citrus/pfsense-backup:latest
    restart: always
    environment:
      - AWS_S3_BUCKET_NAME=${AWS_S3_BUCKET_NAME:-backup-bucket}
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
`--known-hosts FILE` | `PFSENSE_SSH_KNOWN_HOSTS_FILE` | `/root/.ssh/known_hosts` | Known hosts file.

### Service-mode environment variables

Variable | Default | Notes
--- | --- | ---
`AWS_CONFIG_FILE` | `/run/secrets/aws-config` | The externally provided AWS configuration file containing credentials, etc. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`AWS_DRYRUN` | `false` | Set to `true` to pass `--dryrun` to AWS CLI commands.
`AWS_S3_BUCKET_NAME` | | Required parameter. The backup files will be uploaded to this S3 bucket. You may include slashes after the bucket name if you want to upload into a specific path within the bucket, e.g. `your-bucket-name/backups/daily` (without trailing forward slash (`/`)).
`COMPRESSION` | `none` | Compression application to apply: `bzip`, `bzip2`, `bzip3`, `gz`, `gzip`, `lzma`, `lzo`, `lzop`, `none`, `pigz`, `pixz`, `xz`, `zip`
`CRON_EXPRESSION` | `@daily` | Standard debian-flavored `cron` expression for when the backup should run. Use e.g. `0 4 * * *` to back up at 4 AM every night. See the [man page](http://man7.org/linux/man-pages/man8/cron.8.html) or [crontab.guru](https://crontab.guru/) for more.
`DEBUG` | `false` | Set to `true` to enable `xtrace` and `verbose` shell options, and `--verbose` option for `sshpass` and `ssh` client. **WARNING: enables credential exposure in logs — never use in production.**
`GPG_CIPHER_ALGO` | `aes256` | GnuPG symmetric encryption cipher to use to encrypt the backup.
`GPG_PASSPHRASE` | _none_ | GnuPG symmetric encryption pass-phrase to use to encrypt the backup.  **WARNING: consider using the more secure `GPG_PASSPHRASE_FILE`**, which might be a bind mount or a compose secret.
`GPG_PASSPHRASE_FILE` | `/run/secrets/gpg-passphrase` | A file containing the symmetric encryption pass-phrase to use to encrypt the backup. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`HEALTHCHECK_MAX_AGE_SECONDS` | `172800` | Maximum allowed age in seconds of the latest successful backup marker before healthcheck fails. Default is 48 hours.
`HEALTHCHECK_STARTUP_FILE` | `/tmp/pfsense-backup.started-at` | File touched at container startup, used by healthcheck grace-period logic.
`HEALTHCHECK_STARTUP_GRACE_SECONDS` | `900` | Grace period in seconds after container start before requiring a successful backup marker. Default is 15 minutes.
`HEALTHCHECK_SUCCESS_FILE` | `/tmp/pfsense-backup.last-success` | File touched when backup successfully uploads to S3, used by healthcheck recency validation.
`PFSENSE_EXTRA_SSH_ARGS` | _none_ | Additional options to add to the `ssh` command.
`PFSENSE_EXTRA_SSHPASS_ARGS` | _none_ | Additional options to add to the `sshpass` command.
`TAILSCALE_HOST` | _none_ | Specify the hostname or IP address of the pfSense firewall on the Tailscale mesh. Do not include the final `/`, otherwise backup will fail. Used only when `PFSENSE_HOST` is unset.
`TZ` | `UTC` | Which timezone should `cron` use, e.g. `America/New_York` or `Europe/Warsaw`. See [full list of available time zones](http://manpages.ubuntu.com/manpages/bionic/man3/DateTime::TimeZone::Catalog.3pm.html).

## Health check

The container exposes a Docker HEALTHCHECK that validates three things every
30 seconds:

1. **Crontab** — the cron table is configured with the backup command.
2. **crond** — the cron daemon is running.
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

# Run an individual suite
./test/pfsense-backup
./test/backup-success
./test/backup-encryption
./test/backup-xml-validation
./test/backup-aws-failure
./test/healthcheck

# Test against a specific image tag
IMAGE=1121citrus/pfsense-backup:1.2.3 ./test/run-all
```

Tests use lightweight stub binaries in `test/bin/` that shadow the real
`ssh`, `sshpass`, `aws`, and `traceroute` commands inside the container.

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

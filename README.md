# 1121citrus/pfsense-backup

An application specific service to create [pfSense](https://docs.netgate.com/pfsense/en/latest/) backups and copy them to S3.

## Contents

- [Contents](#contents)
- [Synopsis](#synopsis)
- [Overview](#overview)
- [Example: backup periodically as cron job](#example-backup-periodically-as-cron-job)
  - [Example Log Output](#example-log-output)
- [Example: Run "One Off" Backup](#example-run-one-off-backup)
  - [Example Log Output](#example-log-output)
- [Example: Docker compose file](#example-docker-compose-file)
- [Configuration](#configuration)
- [Building](#building)

## Synopsis

- Periodically backup the [pfSense](https://docs.netgate.com/pfsense/en/latest/) router to off site storage (S3).
- Backup files are renamed so they sort by date.
- Credentials are supplied by a compose
[secret](https://docs.docker.com/compose/how-tos/use-secrets/).

## Overview

This service will periodically fetch a [pfSense](https://docs.netgate.com/pfsense/en/latest/) firewall configuration and transfer it to AWS.

You must separately provision and deploy:

1. An SSH key pair. It is recommended that the key pair be created that is
specific to the remote backup task.
2. A user is created on the pfSense system that will be used to copy the
configuration file. The default name is 'remote-backup'.
    1. Grant the user `User - System: Shell account access` privilege
    2. Set the public key as an authorized key for the user and restrict
    it to only copying the config file.
  
  ```console
  $ cat /home/remote-backup/.ssh/authorized_keys 
  restrict,pty,command="cat /cf/conf/config.xml" ssh-ed25519 AAAAC3NzaC1lZDI1MTE5AAAAIFcn7Vcaxi8rQw0/Aw7ZMFfD9h6vOzTXUd/insHick2o remote-backup
  ```

## Example: backup periodically as cron job

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

### Example Log Output

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
[INFO] 20250916T164502 backup compressing backup with lzma/xz --compress --extreme --quiet: 20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz
[INFO] 20250916T164502 backup encrypting backup with GPG
[INFO] 20250916T164503 backup downloaded '20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml' to '20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg'
[INFO] 20250916T164503 backup begin mv '20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg' to S3 bucket 'backups-bucket'
[INFO] 20250916T164503 backup running aws s3 mv --no-progress 20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg s3://backups-bucket/20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg
[INFO] 20250916T164504 backup move: ./20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg to s3://backups-bucket/20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg
[INFO] 20250916T164504 backup completed aws s3 mv --no-progress 20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg s3://backups-bucket/20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg
[INFO] 20250916T164504 backup finish backup
```

## Example: Run "One Off" Backup

Add the `backup` command to the `docker run` command to create a single backup.

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
[INFO] 20250915T013604 backup downloaded '20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml'
[INFO] 20250915T013604 backup begin mv '20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml' to S3 bucket 'backups-bucket'
[INFO] 20250915T013604 backup running aws s3 mv --no-progress 20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml s3://backups-bucket/20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml
[INFO] 20250915T013606 backup move: ./20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml to s3://backups-bucket/20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml
[INFO] 20250915T013606 backup completed aws s3 mv --no-progress 20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml s3://backups-bucket/20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml
[INFO] 20250915T013606 backup finish backup
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

Variable | Default | Notes
--- | --- | ---
`AWS_CONFIG_FILE` | `/run/secrets/aws-config` | The externally provided AWS configuration file containing credentials, etc. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`AWS_DRYRUN` | `false` | Set to `true` to pass `--dryrun` to AWS CLI commands.
`AWS_S3_BUCKET_NAME` |  | Required parameter. The backup files will be uploaded to this S3 bucket. You may include slashes after the bucket name if you want to upload into a specific path within the bucket, e.g. `your-bucket-name/backups/daily` (without trailing forward slash (`/`)).
`COMPRESSION` | `none` | Compression application to apply: `bzip`, `bzip2`, `bzip3`, `gz`, `gzip`, `lzma`, `lzo`, `lzop`, `none`, `pigz`, `pixz`, `xz`, `zip`
`CRON_EXPRESSION` | `@daily` | Standard debian-flavored `cron` expression for when the backup should run. Use e.g. `0 4 * * *` to back up at 4 AM every night. See the [man page](http://man7.org/linux/man-pages/man8/cron.8.html) or [crontab.guru](https://crontab.guru/) for more.
`DEBUG` | `false` | Set to `true` to enable `xtrace` and `verbose` shell options, and `--verbose` option for `sshpass` and `ssh` client.
`GPG_CIPHER_ALGO` | `aes256` | GnuPG symmetric encryption cipher to use to encrypt the backup.
`GPG_PASSPHRASE` | _none_ | GnuPG symmetric encryption pass-phrase to use to encrypt the backup.  WARNING: consider using the more secure `GPG_PASSPHRASE_FILE`, which might be a bind mount or a compose secret.
`GPG_PASSPHRASE_FILE` | `/run/secrets/gpg-passphrase` | A file containing the symmetric encryption pass-phrase to use to encrypt the backup. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`HEALTHCHECK_MAX_AGE_SECONDS` | `172800` | Maximum allowed age in seconds of the latest successful backup marker before healthcheck fails.
`HEALTHCHECK_STARTUP_GRACE_SECONDS` | `900` | Grace period in seconds after container start before requiring a successful backup marker.
`HEALTHCHECK_SUCCESS_FILE` | `/tmp/pfsense-backup.last-success` | File touched when backup successfully uploads to S3, used by healthcheck recency validation.
`PFSENSE_EXTRA_SSH_ARGS` | _none_ | Addition options to add to the `ssh` command.
`PFSENSE_EXTRA_SSHPASS_ARGS` | _none_ | Addition options to add to the `sshpass` command.
`PFSENSE_HOST` | _see notes_ | Specify the hostname or IP address of the pfSense firewall. Do not include the final `/`, otherwise backup will fail. If unset, the script falls back to `TAILSCALE_HOST`, then to the first-hop gateway derived from `traceroute`.
`PFSENSE_IDENTITY_FILE` | `/run/secrets/pfsense-identity` | A file containing the private identity key to access the pfSense system. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`PFSENSE_IDENTITY_PASSWORD` | _none_ | The password to unlock the identity file. WARNING: consider using the more secure `PFSENSE_IDENTITY_PASSWORD_FILE`, which might be a bind mount or a compose secret.
`PFSENSE_IDENTITY_PASSWORD_FILE` | `/run/secrets/pfsense-identity-password` | A file containing the password to unlock the identity file. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`PFSENSE_SSH_KNOWN_HOSTS_FILE` | `/root/.ssh/known_hosts` | Known hosts file used by SSH when host-key checking is enabled.
`PFSENSE_SSH_STRICT_HOST_KEY_CHECKING` | `accept-new` | SSH host-key checking mode (`yes`, `accept-new`, `no`, etc). For best security, use `yes` with a pre-populated known_hosts file.
`PFSENSE_USER` | `remote-backup` | The username to use to access the pfSense system.
`TAILSCALE_HOST` | _none_ | Specify the hostname or IP address of the pfSense firewall on the Tailscale mesh. Do not include the final `/`, otherwise backup will fail. Used only when `PFSENSE_HOST` is unset.
`TZ` | `UTC` | Which timezone should `cron` use, e.g. `America/New_York` or `Europe/Warsaw`. See [full list of available time zones](http://manpages.ubuntu.com/manpages/bionic/man3/DateTime::TimeZone::Catalog.3pm.html).

## Building

1. `docker buildx build --sbom=true --provenance=true --provenance=mode=max --platform linux/amd64,linux/arm64 -t 1121citrus/pfsense-backup:latest -t 1121citrus/pfsense-backup:x.y.z --push .`

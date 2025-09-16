# 1121citrus/pfsense-backup

<!---->An application specific service to create pfSense backups and copy them to S3.

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

- Periodically backup the pfSense router to off site storage (S3).
- Backup files are renamed so they sort by date.
- Credentials are supplied by a compose
[secret](https://docs.docker.com/compose/how-tos/use-secrets/).

## Overview

This service will periodically fetch a pfSense firewall configuration
and transfer it to AWS.

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
20250916T163325 log [INFO] create env file /root/.env
20250916T163325 log [INFO] mode of '/root/.env' changed from 0644 (rw-r--r--) to 0600 (rw-------)
20250916T163325 log [INFO] export AWS_CONFIG_FILE='/run/secrets/aws-config'
20250916T163325 log [INFO] export AWS_DRYRUN='false'
20250916T163325 log [INFO] export AWS_S3_BUCKET_NAME='backups-bucket'
20250916T163325 log [INFO] export CRON_EXPRESSION='*/15 * * * *'
20250916T163325 log [INFO] export DEBUG='false'
20250916T163325 log [INFO] export GPG_CIPHER_ALGO='aes256'
20250916T163325 log [INFO] export GPG_PASSPHRASE='**REDACTED**'
20250916T163325 log [INFO] export GPG_PASSPHRASE_FILE='/run/secrets/gpg-passphrase'
20250916T163325 log [INFO] export PFSENSE_HOST='firewall'
20250916T163325 log [INFO] export PFSENSE_USER=''
20250916T163325 log [INFO] export PFSENSE_IDENTITY_FILE='/run/secrets/pfsense-identity'
20250916T163325 log [INFO] export PFSENSE_IDENTITY_PASSWORD='**REDACTED**'
20250916T163325 log [INFO] export PFSENSE_IDENTITY_PASSWORD_FILE='/run/secrets/pfsense-identity-password'
20250916T163325 log [INFO] export RSA_PUBLIC_KEY_FILE='/run/secrets/rsa-public-key'
20250916T163325 log [INFO] export TAILSCALE_HOST='100.76.132.97'
20250916T163325 log [INFO] installing cron.d entry: /usr/local/bin/backup
20250916T163325 log [INFO] mode of '/var/spool/cron/crontabs/root' changed from 0600 (rw-------) to 0644 (rw-r--r--)
20250916T163325 log [INFO] crontab: */15 * * * * /usr/local/bin/backup 2>&1
20250916T163325 log [INFO] handing the reins over to cron daemon
   .
   .
   .
20250916T164500 log [INFO] begin backup
20250916T164502 log [INFO] compressing backup with lzma/xz --compress --extreme --quiet: 20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz
20250916T164502 log [INFO] encrypting backup with GPT
20250916T164503 log [INFO] downloaded '20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml' to '20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg'
20250916T164503 log [INFO] begin mv '20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg' to S3 bucket 'backups-bucket'
20250916T164503 log [INFO] running aws s3 mv --no-progress 20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg s3://backups-bucket/20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg
20250916T164504 log [INFO] move: ./20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg to s3://backups-bucket/20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg
20250916T164504 log [INFO] completed aws s3 mv --no-progress 20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg s3://backups-bucket/20250916T164502-firewall-1-pfsense-v24.0-config-backup.xml.xz.gpg
20250916T164504 log [INFO] finish backup
```

## Example: Run "One Off" Backup

Add the `backup` command to the `docker run` command to create a single backup.

```console
$ docker run -i --rm \
      -e AWS_S3_BUCKET_NAME=backups-bucket \
      -e CRON_EXPRESSION='* * * * *' \
      -e PFSENSE_HOST=firewall \
      -v ./secrets/aws-config:/run/secrets/aws-config:ro \
      -v ~/.ssh/firewall-remote-backup.ed25519:/run/secrets/pfsense-identity:ro \
      -v ./secrets/pfsense-identity-password:/run/secrets/pfsense-identity-password:ro \
      -v /etc/localtime:/etc/localtime:ro \
      1121citrus/pfsense-backup backup
20250915T013601 backup [INFO] begin backup
20250915T013604 backup [INFO] downloaded '20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml'
20250915T013604 backup [INFO] begin mv '20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml' to S3 bucket 'backups-bucket'
20250915T013604 backup [INFO] running aws s3 mv --no-progress 20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml s3://backups-bucket/20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml
20250915T013606 backup [INFO] move: ./20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml to s3://backups-bucket/20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml
20250915T013606 backup [INFO] completed aws s3 mv --no-progress 20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml s3://backups-bucket/20250915T013604-firewall-1-pfsense-v24.0-config-backup.xml
20250915T013606 backup [INFO] finish backup
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
    file ./pfsense-identity
  pfsense-identity-password:
    file ./pfsense-identity-password
```

## Configuration

Variable | Default | Notes
--- | --- | ---
`AWS_CONFIG_FILE` | `/run/secrets/aws-config` | The externally provided AWS configuration file containing credentials, etc. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`AWS_DRYRUN` | `false` | Set to `true` to pass `--dryrun` to AWS CLI commands.
`AWS_S3_BUCKET_NAME` |  | Required parameter. The backup files will be uploaded to this S3 bucket. You may include slashes after the bucket name if you want to upload into a specific path within the bucket, e.g. `your-bucket-name/backups/daily` (without trailing forward slash (`/`)).
`COMPRESSION` | `none` | Compression application to apply: `bzip`, `bzip2`, `bzip3`, `gz`, `gzip`, `lzma`, `lzo`, `lzop`, `none`, `pigz`, `pixz`, `xz`, `zip`
`CRON_EXPRESSION` | `@daily` | Standard debian-flavored `cron` expression for when the backup should run. Use e.g. `0 4 * * *` to back up at 4 AM every night. See the [man page](http://man7.org/linux/man-pages/man8/cron.8.html) or [crontab.guru](https://crontab.guru/) for more.
`DEBUG` | `false` | Set to `true` to enable `xtrace` and `verbose` shell options, and `--verbose` option for `sshpas` and `ssh` client.
`GPG_CIPHER_ALGO` | `aes256` | GnuPG symmetric encryption cipher to use to encrypt the backup.
`GPG_PASSPHRASE` | _none_ | GnuPG symmetric encryption pass-phrase to use to encrypt the backup.  WARNING: consider using the more secure `GPG_PASSPHRASE_FILE`, which might be a bind mount or a compose secret.
`GPG_PASSPHRASE_FILE` | `/run/secrets/gpg-passphrase` | A file containing the symmetric encryption pass-phrase to use to encrypt the backup. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`PFSENSE_EXTRA_SSH_ARGS` | _none_ | Addition options to add to the `ssh` command.
`PFSENSE_EXTRA_SSHPASS_ARGS` | _none_ | Addition options to add to the `sshpass` command.
`PFSENSE_HOST` | `${TAILSCALE_HOST}` | Specify the hostname or IP address of the pfSense firewall. Do not include the final `/`, otherwise backup will fail.
`PFSENSE_IDENTITY_FILE` | `/run/secrets/pfsense-identity` | A file containing the private identity key to access the pfSense system. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`PFSENSE_IDENTITY_PASSWORD` | _none_ | The password to unlock the identity file. WARNING: consider using the more secure `PFSENSE_IDENTITY_PASSWORD_FILE`, which might be a bind mount or a compose secret.
`PFSENSE_IDENTITY_PASSWORD_FILE` | `/run/secrets/pfsense-identity-password` | A file containing the password to unlock the identity file. This is intended to be a Docker [secret](https://docs.docker.com/compose/how-tos/use-secrets/) but could also be a bind mount.
`PFSENSE_USER` | `remote-backup` | The username to use to access the pfSense system.
`TAILSCALE_HOST` | _see notes_ | Specify the hostname or IP address of the pfSense firewall on the Tailscale mesh. Do not include the final `/`, otherwise backup will fail. Defaults to the gateway IP address if it's a private address.
`TZ` | `UTC` | Which timezone should `cron` use, e.g. `America/New_York` or `Europe/Warsaw`. See [full list of available time zones](http://manpages.ubuntu.com/manpages/bionic/man3/DateTime::TimeZone::Catalog.3pm.html).

## Building

1. `docker buildx build --sbom=true --provenance=true --provenance=mode=max --platform linux/amd64,linux/arm64 -t 1121citrus/pfsense-backup:latest -t 1121citrus/pfsense-backup:x.y.z --push .`

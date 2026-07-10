# Security

## Reporting a Vulnerability

Please report security vulnerabilities through the [GitHub Security tab](https://github.com/1121citrus/pfsense-backup/security).
Do not open a public GitHub issue for security vulnerabilities.

---

## Threat Model

`pfsense-backup` connects to a pfSense firewall over SSH, downloads the
configuration file, optionally compresses and encrypts it, then uploads it to
an S3 bucket. The attack surface is limited to:

1. The SSH connection to the pfSense host.
2. The AWS credential used for S3 uploads.
3. The GPG passphrase used to encrypt backups (optional).
4. The container environment itself.

---

## CVE Status (Last Reviewed 2026-07-10)

Advisory scans are run with Trivy (gating), Grype, and Docker Scout. The
tables below reflect the current validated scan posture for the digest pinned
in this repository.

### Trivy (Gating Scan)

| Result | Notes |
| --- | --- |
| **0 vulnerabilities** | Gating scan passes; build is not blocked. |

### Open Vulnerabilities

The gating Trivy scan is clean, but advisory feeds still report the items below.

| Status | CVE / Advisory | Component | Notes |
| --- | --- | --- | --- |
| Upstream unavailable | `CVE-2026-44431`, `CVE-2026-44432` | `urllib3` | Docker Scout reports `urllib3@2.6.3` as HIGH. The fixed version is `2.7.0`, which is not yet published to the package index consumed by the image build. |
| Scout metadata / feed issue | `CVE-2023-31484`, `CVE-2023-31486` | AL2023 `perl` subpackages | Docker Scout still reports these against AL2023 `perl` virtual/meta package entries even though the reported installed release (`5.32.1-477.amzn2023.0.8`) is newer than Scout's stated fixed releases (`.0.4` / `.0.5`). The runtime image does not install the top-level `perl` RPM directly. |
| Scout stale package detection | `CVE-2026-44431` | `urllib3@1.25.10` | Docker Scout also reports a stale `urllib3@1.25.10` package record alongside the current `urllib3@2.6.3`. Trivy and the runtime validation see the current package set, and the image runs with `pip 26.0.1` and `urllib3 2.6.3`. |
| Resolved by base refresh | `CVE-2026-42504` | `supercronic` Go stdlib | `pfsense-backup` now pins the refreshed `aws-backup-base` digest `sha256:8ec7c8f3481295df72baf8f80c948db56d5a2d62e725260dda7e66d8c57243ad`. Re-run Docker Scout against the rebuilt child image after the next staging pass to confirm the advisory clears. |

### Remediated Vulnerabilities

| CVE / Advisory | Component | Remediation |
| --- | --- | --- |
| Alpine APK CVEs (multiple) | `python3`, `busybox`, `openssh`, `unzip`, `sqlite`, `py3-urllib3`, `py3-cryptography` | Resolved by migrating base image from Alpine 3.22 to AL2023 (v1.0.5) |
| CVE-2026-32280 — CVE-2026-33810 | supercronic Go stdlib | Resolved: `aws-backup-base` now ships supercronic v0.2.45 (Go ≥1.26.2) |
| CVE-2026-26007 | cryptography (pip) | Pinned `cryptography>=47.0.0` in `requirements.txt` (via `aws-backup-base`) |
| CVE-2026-21441, CVE-2025-66471, CVE-2025-66418 | urllib3 (pip) | Pinned `urllib3>=2.6.3` in `requirements.txt` (via `aws-backup-base`) |
| CVE-2026-24049 | wheel (pip) | Pinned `wheel>=0.47.0` in `requirements.txt` (via `aws-backup-base`) |
| CVE-2025-8869, CVE-2026-8643, CVE-2026-6357, CVE-2026-3219 | pip | Upgraded to `pip>=26.0.1` during the image build |
| CVE-2024-5569 | zipp (pip) | Pinned `zipp>=3.23.1` in `requirements.txt` (via `aws-backup-base`) |

### Scout-Specific Notes

Docker Scout is treated as advisory in staging because its feed and package
inventory can lag the runtime state observed by Trivy and the live container.
Current examples include:

1. A stale `urllib3@1.25.10` record even after the runtime upgrades to `urllib3 2.6.3`.
2. Repeated `perl` HIGH findings tied to AL2023 package metadata where the installed release is already newer than Scout's cited fixed version.
3. Long-running scans that may exceed the staging timeout budget; these runs are allowed to continue as advisory-only.

---

## Hardening Checklist

### SSH Key Restriction (Critical)

The SSH key used for backups **must** be restricted on the pfSense side so it
can only execute `cat /cf/conf/config.xml`. Without this restriction a stolen
key grants arbitrary shell access.

```text
restrict,pty,command="cat /cf/conf/config.xml" ssh-ed25519 AAAA... remote-backup
```

Add this to `/home/remote-backup/.ssh/authorized_keys` on the pfSense system.
The `restrict` option disables port forwarding, agent forwarding, and X11
forwarding in addition to locking the command.

### Host Key Verification

The default `PFSENSE_SSH_STRICT_HOST_KEY_CHECKING=accept-new` trusts a host
on **first connection** but rejects changed keys thereafter. This is
vulnerable to a machine-in-the-middle attack on the very first backup run.

For production deployments, set `PFSENSE_SSH_STRICT_HOST_KEY_CHECKING=yes`
and pre-populate the known-hosts file:

```bash
ssh-keyscan -H <pfsense-host> >> ./secrets/known_hosts
```

Then mount it:

```yaml
volumes:
  - ./secrets/known_hosts:/root/.ssh/known_hosts:ro
```

### Credential Storage

**Prefer Docker secrets (files) over environment variables** for all
sensitive values. Environment variables are visible via `docker inspect`,
`/proc/<pid>/environ`, and container runtime APIs.

| Secret | Recommended mechanism |
| --- | --- |
| SSH key | Docker secret → `/run/secrets/pfsense-identity` |
| SSH key passphrase | Docker secret → `/run/secrets/pfsense-identity-password` |
| GPG passphrase | Docker secret → `/run/secrets/gpg-passphrase` |
| AWS credentials | Docker secret → `/run/secrets/aws-config` |

The `PFSENSE_IDENTITY_PASSWORD` and `GPG_PASSPHRASE` environment variables are
supported for convenience but should only be used in trusted, isolated
environments.

### sshpass -p Process Visibility

When `PFSENSE_IDENTITY_PASSWORD` (env var) is used, the passphrase is passed
to `sshpass` via `-p` and is briefly visible in `/proc/<pid>/cmdline` on the
host while the process runs. The file-based path (`-f`) is not affected.

### DEBUG Mode

`DEBUG=true` enables shell `xtrace` and `verbose` modes, which print every
command to stderr **including commands that contain credentials**. Never
enable `DEBUG=true` in production or in any environment where logs are
collected or forwarded.

### Container Privilege

The container runs as the dedicated `pfsense-backup` user (UID 10001, shell
`/sbin/nologin`). In scheduler mode, `pfsense-backup --cron` writes the
schedule file to `/var/spool/cron/crontabs/pfsense-backup` and execs
`supercronic` as that user. The `~/.gnupg` and `~/.ssh` directories are
created in the user's home directory (`/pfsense-backup`) with mode `700`.
No process inside the container listens on a network port.

---

## Dependency Supply Chain

The image extends `1121citrus/aws-backup-base` (Amazon Linux 2023). Additional
packages are installed via `dnf` and Python packages via pip with minimum
version constraints in `requirements.txt`. The CI pipeline runs
[Trivy](https://github.com/aquasecurity/trivy), Grype, and Docker Scout
vulnerability scans against the pushed image on every merge to `main`.

Multi-platform images pushed to Docker Hub include:

- **SBOM** (Software Bill of Materials) — OCI attestation listing all
  installed packages and their versions.
- **SLSA provenance** (`mode=max`) — full build graph attestation including
  source inputs and build environment.

Verify attestations with:

```bash
docker buildx imagetools inspect 1121citrus/pfsense-backup:latest \
  --format '{{ json .Provenance }}'
```

---

## S3 Bucket Hardening

The S3 bucket receiving backups should be configured as:

- **Block all public access** enabled.
- **Server-side encryption** (SSE-S3 or SSE-KMS) enabled.
- **Versioning** enabled so accidental overwrites or deletions are recoverable.
- **MFA delete** enabled for the bucket to prevent accidental or malicious
  deletion of version history.
- **Lifecycle rules** to expire old backups after a retention period.
- **Bucket policy** restricting `s3:PutObject` to the IAM role/user used by
  the container. No `s3:DeleteObject` permissions are required.

Minimal IAM policy for the backup user:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject"],
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/*"
    }
  ]
}
```

Note: `aws s3 mv` requires both `PutObject` (upload) and `DeleteObject`
(remove the temporary local copy — which runs inside the container, not in S3).
The delete happens locally; no S3 delete permission is needed.

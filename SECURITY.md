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

## CVE Status (Last Reviewed 2026-04-25)

Advisory scans are run with Trivy (gating), Grype, and Docker Scout. The
tables below reflect the state after the most recent build.

### Trivy (Gating Scan)

| Result | Notes |
| --- | --- |
| **0 vulnerabilities** | Gating scan passes; build is not blocked. |

### Fixed by Dockerfile Pip Upgrade

The following CVEs were remediated by pip-installing patched versions over
the Alpine-packaged versions (or pip's own bundled dependencies). The pip
step runs in the same `RUN` layer as the `apk add` installs.

| Package | Installed (apk/pip) | Fixed (pip) | CVEs | Severity |
| --- | --- | --- | --- | --- |
| `cryptography` | 44.0.3-r0 | ≥46.0.5 | CVE-2026-26007 | High |
| `urllib3` | 1.26.20-r1 | ≥2.6.3 | CVE-2026-21441, CVE-2025-66471, CVE-2025-66418 | High |
| `wheel` | 0.45.1 (pip dep) | ≥0.46.2 | CVE-2026-24049 | High |
| `pip` | 25.1.1-r0 | ≥25.3 | CVE-2025-8869 | Medium |
| `zipp` | 3.17.0 (pip dep) | ≥3.19.1 | CVE-2024-5569 | Medium |

### Fixed by Supercronic Upgrade

| Package | Old Version | New Version | CVEs Fixed | Severity |
| --- | --- | --- | --- | --- |
| `supercronic` | v0.2.44 (Go 1.26.1) | v0.2.45 (Go ≥1.26.2) | CVE-2026-32280, CVE-2026-32281, CVE-2026-32282, CVE-2026-32283, CVE-2026-33810 | High |

### Unfixed — No Patch Available in Alpine 3.22

The following findings have no available fix. None affect the primary threat
surface (see threat model above).

| Package | Version | CVE | Severity | Notes |
| --- | --- | --- | --- | --- |
| `python3` | 3.12.13-r0 | CVE-2025-13836 | High | No Alpine fix available |
| `unzip` | 6.0-r15 | CVE-2008-0888 | High | No Alpine fix; unzip not network-facing |
| `sqlite` | 3.49.2-r1 | CVE-2025-70873 | High | No Alpine fix; sqlite is a transitive dependency |
| `py3-urllib3` (apk) | 1.26.20-r1 | CVE-2025-66471, CVE-2025-66418 | High | Alpine apk metadata superseded by pip-installed urllib3 ≥2.6.3; advisory scanners may still flag the apk metadata entry |
| `py3-cryptography` (apk) | 44.0.3-r0 | CVE-2026-26007 | High | Alpine apk metadata superseded by pip-installed ≥46.0.5; advisory scanners may still flag the apk metadata entry |
| `py3-pip` (apk) | 25.1.1-r0 | CVE-2025-8869, CVE-2026-1703 | Med/Low | Alpine apk metadata superseded by pip-installed ≥25.3; advisory scanners may still flag the apk metadata entry |
| `wheel` (pip-vendored) | 0.45.1 | CVE-2026-24049 | High | pip internally vendors a copy of wheel for bootstrap; distinct from the standalone package (upgraded to ≥0.46.2). Cannot be upgraded externally. Trivy confirms 0 vulns for the standalone installed package. |
| `busybox` | 1.37.0-r20 | CVE-2025-60876 | Medium | No Alpine fix available |
| `openssh` | 10.0_p1-r10 | CVE-2026-35414 | Medium | No Alpine fix available |
| `openldap` | 2.6.8-r0 | CVE-2026-22185 | Medium | No Alpine fix; openldap is a transitive dependency |
| `gnupg` (and sub-packages) | 2.4.9-r0 | CVE-2022-3219 | Low | No Alpine fix |
| `lz4` | 1.10.0-r0 | CVE-2025-62813 | Unspecified | No Alpine fix; lz4 is a transitive dependency |

### False Positives

| Package | Version | CVE | Tool | Reason |
| --- | --- | --- | --- | --- |
| `py3-jmespath` | 1.0.1-r4 | CVE-2022-32511 | Grype | Fixed in jmespath 1.0.1; installed version 1.0.1-r4 is at or above the fix version — Grype stale database entry |

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

The `Dockerfile` installs packages from the Alpine Linux APK repository. All
packages are version-pinned with minimum version constraints. The CI pipeline
runs a [Trivy](https://github.com/aquasecurity/trivy) vulnerability scan
against the pushed image on every merge to `main`.

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

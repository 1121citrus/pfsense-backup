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

## CVE Status (Last Reviewed 2026-08-02)

Advisory scans are run with Trivy (gating), Grype, and Docker Scout. The
tables below reflect the current validated scan posture for the digest pinned
in this repository.

### Trivy (Gating Scan)

| Result | Notes |
| --- | --- |
| **0 vulnerabilities** | Gating scan passes after `.trivyignore` suppression of the entries below; build is not blocked. |

### Open Vulnerabilities

The gating Trivy scan passes only via `.trivyignore` suppression; advisory
feeds still report the items below.

| Status | CVE / Advisory | Component | Notes |
| --- | --- | --- | --- |
| Upstream unavailable | `CVE-2026-58010`–`CVE-2026-58016` | `glib2` (AL2023, inherited from `aws-backup-base`) | Fix `2.82.2-770.amzn2023` not yet in the AL2023 repos. Also reported by Grype/Scout as `ALAS2023-2026-1942`. Already suppressed in `aws-backup-base`'s own `.trivyignore`; mirrored here since suppression is scan-time, not baked into the base image. Confirmed still unavailable via `dnf check-update` on 2026-08-02. |
| Upstream unavailable | `CVE-2026-54369`, `CVE-2026-54370` | `libacl` / `acl` (AL2023) | Fix `2.4.0-1.amzn2023.0.1` not yet in the AL2023 repos. Also reported by Grype/Scout as `ALAS2023-2026-1986`. Confirmed still unavailable via `dnf check-update` on 2026-08-02. |
| Upstream unavailable | `CVE-2026-0864`, `CVE-2026-11940`, `CVE-2026-11972`, `CVE-2026-3276`, `CVE-2026-9669` | `python3` / `python3-libs` (AL2023) | Fix `3.9.25-1.amzn2023.0.8` not yet in the AL2023 repos. Also reported by Grype/Scout as `ALAS2023-2026-1963`. Confirmed still unavailable via `dnf check-update` on 2026-08-02. |
| Blocked by Python version floor | `CVE-2026-44431`, `CVE-2026-44432` | `urllib3` (pip-managed copy, `/usr/local`, currently `2.6.3`) | Fixed in `urllib3 2.7.0`, but that release requires Python >= 3.10 (confirmed against PyPI release metadata: `urllib3==2.7.0` declares `requires_python: ">=3.10"`). This image's base (`aws-backup-base`, AL2023) ships Python 3.9, so `pip3 install --upgrade urllib3>=2.7.0` fails to resolve — verified directly against this image; see `CHANGELOG.md` [1.0.14]. No fix is installable until the base image's Python is upgraded. Suppressed via `.trivyignore`/`.trivyignore.yaml`/`.grype.yaml`. |
| No safe remediation path | `CVE-2026-21441`, `CVE-2025-66471`, `CVE-2025-66418`, `CVE-2021-33503`, `CVE-2026-44431`, `CVE-2023-43804` | `urllib3` (RPM-managed system copy, `python3-urllib3` package, currently `1.25.10`) | This is a *separate* on-disk copy from the pip-managed `urllib3` under `/usr/local` (see "AWS CLI Python Isolation" below) — no AL2023 package fix is available, and overwriting RPM-tracked files with `pip install --target` risks breaking `aws`. Left in place and suppressed via `.grype.yaml`. |
| No safe remediation path | `CVE-2022-40897`, `CVE-2025-47273`, `CVE-2024-6345` | `setuptools` (RPM-managed system copy, `python3-setuptools` package, currently `59.6.0`) | Same root cause as the `urllib3` entry above — no AL2023 package fix available for the RPM-managed copy actually used by `aws`. Suppressed via `.grype.yaml`. |
| Scout metadata / feed issue | `CVE-2023-31484`, `CVE-2023-31486` | AL2023 `perl` subpackages | Docker Scout still reports these against AL2023 `perl` virtual/meta package entries even though the reported installed release (`5.32.1-477.amzn2023.0.8`) is newer than Scout's stated fixed releases (`.0.4` / `.0.5`). The runtime image does not install the top-level `perl` RPM directly. |
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

1. A stale `urllib3@1.25.10` record alongside the current `urllib3@2.6.3`.
2. Repeated `perl` HIGH findings tied to AL2023 package metadata where the installed release is already newer than Scout's cited fixed version.
3. Reported "fixed version" values (e.g. `urllib3 2.7.0`, `pip 26.1.2`) that exist upstream but are not actually installable on this image: both require Python >= 3.10, while this image's base ships Python 3.9. A Dockerfile bump to those pins was attempted and reverted after confirming (via a direct rebuild) that `pip3 install` cannot resolve them under Python 3.9. Treat Scout/Trivy/Grype "fix available" annotations as informational only until cross-checked against the target Python's compatibility, not as evidence a bump is safe to make.
4. Long-running scans that may exceed the staging timeout budget; these runs are allowed to continue as advisory-only.

#### AWS CLI Python Isolation (image hygiene caveat)

`/usr/bin/aws` (AWS CLI v2, RPM-installed by `aws-backup-base`) has the
shebang `#!/usr/bin/python3 -s`. On this AL2023 image, running Python with
`-s` excludes **both** `/usr/local/lib/python3.9/site-packages` **and**
`/usr/local/lib64/python3.9/site-packages` from `sys.path` (verified via
`python3 -s -c "import sys; print(sys.path)"` inside the built image) —
only the RPM-managed `/usr/lib(64)/python3.9/site-packages` directories are
visible. This means the `pip3 install --upgrade` step in the `Dockerfile`
(`cryptography`, `urllib3`, `wheel`, `zipp`) protects only code that runs
under a plain `python3` invocation; it does **not** change which
`urllib3`/`setuptools`/`idna`/`pygments` versions `aws` itself resolves at
runtime, since `aws` never sees `/usr/local`. `aws` continues to run against
the older RPM-managed copies (`python3-urllib3 1.25.10`,
`python3-setuptools 59.6.0`, etc.) regardless of any pip upgrades — see the
"No safe remediation path" rows above. Note that, independently of this
isolation issue, the pip-managed `/usr/local` copy of `urllib3` is itself
capped at `2.6.3` by the base image's Python 3.9 (see the "Blocked by
Python version floor" row above) — so upgrading the pip-managed copy
would not currently be possible even if `aws` could see it.

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

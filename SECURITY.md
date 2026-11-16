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

## CVE Status (Last Reviewed 2026-11-15)

Advisory scans are run with Trivy (gating), Grype, and Docker Scout. The
tables below reflect the current validated scan posture for the digest pinned
in this repository: `aws-backup-base` 1.2.3,
`sha256:dc4c176e47b9d1b818c149466bcb61ed2e5ea643a0d947d6b8fc8519b2b14852`.

### Trivy (Gating Scan)

| Result | Notes |
| --- | --- |
| **0 vulnerabilities** | No suppressions. An unfiltered scan (no ignore file, all severities, including unfixed) reports zero findings (verified 2026-11-15). `.trivyignore`/`.trivyignore.yaml` carry no entries. |

### Open Vulnerabilities

Grype reports one finding, which `.grype.yaml` suppresses: `urllib3`
GHSA-q2q7-5pp4-w6pg (CVE-2021-33503), which AL2023 rates "Not Affected".

`python3-urllib3` and `python3-idna` are runtime dependencies of
`awscli-2`. The installed builds (`python3-urllib3-1.25.10-5.amzn2023.0.9`,
`python3-idna-2.10-3.amzn2023.0.4`) are the latest that AL2023 publishes.
AL2023 backports fixes without changing the upstream `1.25.10` / `2.10`
version strings, so scanners that read package metadata report CVEs that
the installed RPMs already fix.

Docker Scout (0C 7H 6M 0L) reports the following findings, which cannot be
fixed in this repository:

| CVE | Component | Why it remains |
| --- | --- | --- |
| CVE-2023-45803, CVE-2025-50181, CVE-2025-66418, CVE-2025-66471, CVE-2026-21441, CVE-2026-44431, CVE-2026-97689 | `urllib3` 1.25.10 | False positives. Each is listed as fixed in `rpm -q --changelog python3-urllib3` |
| CVE-2021-33503 (HIGH) | `urllib3` 1.25.10 | AL2023 rates the package "Not Affected". Suppressed in `.grype.yaml` |
| CVE-2023-43804 (HIGH), CVE-2024-37891 (MEDIUM) | `urllib3` 1.25.10 | Residual risk accepted. The RPM changelog does not list a fix, and AL2023 has no newer build. The AWS CLI only connects to AWS endpoints over HTTPS, which limits exposure to the cookie and proxy-header leaks these describe |
| CVE-2024-3651, CVE-2026-45409 | `idna` 2.10 | False positives. Each is listed as fixed in `rpm -q --changelog python3-idna` |
| CVE-2026-19617 (MEDIUM) | `lvm2` / `device-mapper-libs` | False positive. Scout compares the `device-mapper-libs` version (`1.02.185-1.amzn2023.0.6`) against the `lvm2` source package version. The installed RPM is built from `lvm2-2.03.16-1.amzn2023.0.6.src.rpm`, which is the fixed version Scout names |

If a new finding has no fixed AL2023 build (confirm with
`dnf --releasever=latest list --showduplicates <pkg>`), add it to
`.trivyignore.yaml`/`.grype.yaml` with a dated justification and list it
here.

### Resolved 2026-11-15

`dnf install`/`upgrade`/`reinstall` now run with `--releasever=latest`, and
the base digest moved from `aws-backup-base` 1.1.9
(`sha256:a9cd5e66...3193c70a4`, supercronic v0.2.47 built with Go 1.26.5)
to 1.2.3 (supercronic v0.2.49 built with Go 1.27.4). This cleared 172
gating HIGH findings without suppression: 160 AL2023 OS-package findings
(including `curl-minimal`/`libcurl-minimal`, `glibc`, `systemd`, `python3`,
and `rpm`) and 12 `supercronic` Go stdlib findings. Every earlier AL2023
OS-package and Go stdlib suppression (`glib2`, `libacl`, `python3`,
`gnutls`, `libsolv`, `libcap`, `glibc`, `openssh`, `CVE-2026-42504`) was
removed from `.trivyignore`/`.trivyignore.yaml`: the installed packages now
contain the fixes.

The image also stopped installing pip packages and `python3-pip`, and now
removes `perl`, `python3-setuptools`, `python3-setuptools-wheel`, and
`python3-pip-wheel`. `/usr/bin/aws` runs as `python3 -s` (see "AWS CLI
Python Isolation" below) and no script runs `python3`, so none of these
were used at runtime. This removed the pip-managed `urllib3` 2.6.3 copy and
its Python 3.9-blocked findings (`CVE-2026-44431`, `CVE-2026-44432`,
`CVE-2026-97687`, `CVE-2026-97688`, `CVE-2026-97689`), the `setuptools`
59.6.0 and `pip` 21.3.1 and 26.0.1 findings, and the `perl-*` Scout false
positives (`CVE-2023-31484`, `CVE-2023-31486`). Docker Scout dropped from
0C 60H 202M 2L to 0C 7H 6M 0L, and every Trivy suppression and all but one
Grype suppression were removed.

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

1. `urllib3@1.25.10`, `idna@2.10`, and `lvm2` findings that the installed AL2023 RPMs already fix (see "Open Vulnerabilities" above).
2. Reported "fixed version" values (e.g. `urllib3 2.7.0`, `pip 26.1.2`) that exist upstream but are not actually installable on this image: both require Python >= 3.10, while this image's base ships Python 3.9. A Dockerfile bump to those pins was attempted and reverted after confirming (via a direct rebuild) that `pip3 install` cannot resolve them under Python 3.9. Treat Scout/Trivy/Grype "fix available" annotations as informational only until cross-checked against the target Python's compatibility, not as evidence a bump is safe to make.
3. Long-running scans that may exceed the staging timeout budget; these runs are allowed to continue as advisory-only.

#### AWS CLI Python Isolation (image hygiene caveat)

`/usr/bin/aws` (AWS CLI v2, RPM-installed by `aws-backup-base`) has the
shebang `#!/usr/bin/python3 -s`. On this AL2023 image, running Python with
`-s` excludes **both** `/usr/local/lib/python3.9/site-packages` **and**
`/usr/local/lib64/python3.9/site-packages` from `sys.path` (verified via
`python3 -s -c "import sys; print(sys.path)"` inside the built image) —
only the RPM-managed `/usr/lib(64)/python3.9/site-packages` directories are
visible. A pip-installed package under `/usr/local` therefore protects
only code that runs under a plain `python3` invocation, and nothing in
this image does. This is why the image installs no pip packages: an earlier
`pip3 install --upgrade` step (`cryptography`, `urllib3`, `wheel`, `zipp`)
never changed what `aws` loads, and its `urllib3` 2.6.3 copy only added
scanner findings. `aws` runs against the RPM-managed copies
(`python3-urllib3` 1.25.10, `python3-idna` 2.10), which AL2023 patches by
backport.

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
packages are installed via `dnf`; the image installs no pip packages. The CI pipeline runs
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

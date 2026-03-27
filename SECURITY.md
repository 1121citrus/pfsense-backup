# Security

## Reporting a Vulnerability

Please report security vulnerabilities through the [GitHub Security tab](https://github.com/1121citrus/pfsense-backup/security).
Do not open a public GitHub issue for security vulnerabilities.

---

## Known Vulnerabilities (Documented Exceptions)

### urllib3: Data Amplification (CVE-2026-21441, CVE-2025-66471)

- **Component**: urllib3 (transitive via aws-cli → botocore)
- **Affected Versions**: urllib3 < 2.6.0 (CVE-2025-66471), < 2.6.3 (CVE-2026-21441)
- **Description**: Decompression bomb attack via highly compressed HTTP response bodies
- **Attack Vector**: Requires malicious or compromised HTTP server to send specially crafted compressed response
- **Mitigation in pfsense-backup**:
  - Connects **only** to pfSense host via **SSH** (not HTTP)
  - Connects **only** to AWS S3 via **HTTPS** with certificate validation
  - Both are fixed, trusted endpoints; no untrusted HTTP sources
  - The vulnerability requires attacker control of the HTTP server, which is not applicable here
- **Status**: Acknowledged but not exploitable in this deployment model
- **Expiry**: 2027-06-17

### urllib3: Resource Allocation Without Limits (CVE-2025-66418)

- **Component**: urllib3 (transitive via aws-cli → botocore)
- **Affected Versions**: urllib3 < 2.6.0
- **Description**: Header parsing DoS via malformed HTTP headers causing unbounded memory allocation
- **Attack Vector**: Requires malicious HTTP server or MITM to send malformed headers
- **Mitigation in pfsense-backup**:
  - Communicates only with trusted AWS S3 and pfSense (via SSH)
  - AWS S3 API returns well-formed HTTP headers
  - No processing of untrusted HTTP input
- **Status**: Acknowledged but not exploitable in this deployment model
- **Expiry**: 2027-06-17

### cryptography: Insufficient ECDSA Signature Verification (CVE-2026-26007)

- **Component**: cryptography (transitive via aws-cli → botocore)
- **Affected Versions**: cryptography < 46.0.5
- **Description**: ECDSA signature validation may not properly verify data authenticity
- **Attack Vector**: Requires attacker-controlled ECDSA signatures
- **Mitigation in pfsense-backup**:
  - cryptography is used for GPG encryption/decryption of backup files (optional)
  - ECDSA signature verification is **not used** in pfsense-backup's workflow
  - GPG uses RSA or ElGamal, not ECDSA
  - The vulnerability is not reachable through pfsense-backup's cryptographic operations
- **Status**: Acknowledged but not exploitable in this deployment model
- **Expiry**: 2027-06-17

---

`pfsense-backup` connects to a pfSense firewall over SSH, downloads the
configuration file, optionally compresses and encrypts it, then uploads it to
an S3 bucket.  The attack surface is limited to:

1. The SSH connection to the pfSense host.
2. The AWS credential used for S3 uploads.
3. The GPG passphrase used to encrypt backups (optional).
4. The container environment itself.

---

## Hardening Checklist

### SSH Key Restriction (Critical)

The SSH key used for backups **must** be restricted on the pfSense side so it
can only execute `cat /cf/conf/config.xml`.  Without this restriction a stolen
key grants arbitrary shell access.

```text
restrict,pty,command="cat /cf/conf/config.xml" ssh-ed25519 AAAA... remote-backup
```

Add this to `/home/remote-backup/.ssh/authorized_keys` on the pfSense system.
The `restrict` option disables port forwarding, agent forwarding, and X11
forwarding in addition to locking the command.

### Host Key Verification

The default `PFSENSE_SSH_STRICT_HOST_KEY_CHECKING=accept-new` trusts a host
on **first connection** but rejects changed keys thereafter.  This is
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
sensitive values.  Environment variables are visible via `docker inspect`,
`/proc/<pid>/environ`, and container runtime APIs.

| Secret | Recommended mechanism |
|---|---|
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
host while the process runs.  The file-based path (`-f`) is not affected.

### DEBUG Mode

`DEBUG=true` enables shell `xtrace` and `verbose` modes, which print every
command to stderr **including commands that contain credentials**.  Never
enable `DEBUG=true` in production or in any environment where logs are
collected or forwarded.

### Container Privilege

The container runs as the dedicated `pfsense-backup` user (UID 10001, shell
`/sbin/nologin`).  The crontab is written to
`/var/spool/cron/crontabs/pfsense-backup`; busybox `crond` reads it as that
user.  The `~/.gnupg` and `~/.ssh` directories are created in the user's home
directory (`/home/pfsense-backup`) with mode `700`.  No process inside the
container listens on a network port.

---

## Dependency Supply Chain

The `Dockerfile` installs packages from the Alpine Linux APK repository.  All
packages are version-pinned with minimum version constraints.  The CI pipeline
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
  the container.  No `s3:DeleteObject` permissions are required.

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

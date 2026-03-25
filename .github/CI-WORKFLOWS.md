# GitHub CI Workflows

Automated linting, building, testing, security scanning, and Docker image publication for pfsense-backup.

## Workflow Overview

| Stage        | Trigger                               | Purpose                                        |
| ------------ | ------------------------------------- | ---------------------------------------------- |
| **Lint**     | All pushes, PRs to main/master, tags  | Validate Dockerfile and shell scripts          |
| **Build**    | After lint                            | Build image and share as artifact              |
| **Tests**    | After build (6 jobs, parallel)        | Run each test suite independently              |
| **Scan**     | After build (parallel with tests)     | Trivy image scan — blocks push on fixable CVEs |
| **Push**     | Version tags and staging branch only  | Multi-platform build and push to Docker Hub    |

## CI Workflow (`ci.yml`)

Single unified workflow for all CI/CD stages.

### Trigger Events

- **Push:** `main`, `master`, `staging` branches and `v*` version tags
- **Pull requests:** `main`, `master` branches

### Versioning

Tag-driven. Push a git tag to publish a release:

```bash
git tag v1.2.3
git push origin v1.2.3
# Publishes: 1121citrus/pfsense-backup:1.2.3 + :latest
```

No automation bumps the version — the tag is always a deliberate decision.

---

## Stage 1: Lint

- **Hadolint** — Dockerfile best-practice checks
- **ShellCheck** — static analysis of `src/` and `test/` shell scripts
  - `--exclude=SC1090,SC1091,SC2148` — suppresses source-following warnings:
    SC1090 (dynamic path), SC1091 (absolute install-time path not resolvable at lint time),
    SC2148 (intentionally sourced library files without a shebang)

---

## Stage 2: Build

Builds image for `linux/amd64` (the runner's native platform) and exports as a GitHub Actions artifact (`docker-image`). The image is re-tagged as `:latest` so test scripts that default to `IMAGE:latest` work without modification.

Artifact retention: 1 day.

---

## Stage 3: Tests (parallel)

Six test jobs run simultaneously after build, each exercising a distinct behaviour:

| Job                   | Script                       | What it tests                  |
| --------------------- | ---------------------------- | ------------------------------ |
| `test-required-vars`  | `test/backup-required-vars`  | Required environment variables |
| `test-backup-success` | `test/backup-success`        | Successful backup operation    |
| `test-encryption`     | `test/backup-encryption`     | Backup encryption              |
| `test-xml-validation` | `test/backup-xml-validation` | pfSense XML config validity    |
| `test-aws-failure`    | `test/backup-aws-failure`    | AWS upload error handling      |
| `test-healthcheck`    | `test/healthcheck`           | Container health check         |

Each job downloads the shared artifact independently to run in parallel.

---

## Stage 4: Security scan

Runs in parallel with the test jobs. Scans the local image **before** it is pushed to Docker Hub.

- **Tool:** Trivy `aquasecurity/trivy-action@0.35.0` (pinned)
- **Severity:** CRITICAL, HIGH
- **Blocking:** `exit-code: 1` — fails and blocks push if fixable CVEs found
- **Noise reduction:** `ignore-unfixed: true` — suppresses CVEs with no available patch
- **DB caching:** `~/.cache/trivy` is cached between runs with `actions/cache`; the vulnerability DB is
  only re-downloaded when the cache is cold or the DB has been updated
- **Download noise:** `TRIVY_NO_PROGRESS=true` suppresses progress bars; `TRIVY_QUIET=true` suppresses
  `INFO [vulndb]` log lines during DB download

---

## Stage 5: Push to Docker Hub

Runs only when all tests and the scan pass, and only on version tags or the staging branch.

### Tagging

| Trigger           | Docker Hub tags                                         |
| ----------------- | ------------------------------------------------------- |
| Tag `v1.2.3`      | `1121citrus/pfsense-backup:1.2.3` + `:latest`           |
| Push to `staging` | `1121citrus/pfsense-backup:staging-<timestamp>` + `:staging` |

- `:latest` is set **only** on version-tagged releases
- Staging gets a datetime timestamp for traceability

### Build configuration

- **Platforms:** `linux/amd64`, `linux/arm64`
- **Attestations:** `sbom: true` + `provenance: mode=max` (SLSA L3)

---

## Execution Flow

```
On push/PR
    ↓
[Lint] — hadolint + shellcheck
    ↓
[Build] — single-arch image → artifact
    ↓ (parallel — 7 jobs)
[test-required-vars]   [test-backup-success]   [test-encryption]
[test-xml-validation]  [test-aws-failure]       [test-healthcheck]
[scan] — Trivy CRITICAL/HIGH

[Push] (tags and staging only, after all 7 pass)
 - QEMU + Buildx multi-arch
 - push amd64 + arm64
 - SBOM + provenance
```

---

## Configuration Reference

### Required Secrets

- `DOCKERHUB_USERNAME` — Docker Hub account
- `DOCKERHUB_TOKEN` — Docker Hub access token

### Key Files

- `Dockerfile` — Container build definition
- `build` — Build helper script (shellchecked)
- `src/backup` — Main backup script
- `src/common-functions` — Shared shell library
- `test/run-all` — Test orchestrator
- `test/backup-*`, `test/healthcheck` — Test scripts run as CI jobs
- `test/bin/` — Mock binaries (aws, ssh, sshpass, traceroute)
- `test/pfsense-backup` — Tests `src/backup` directly (shellchecked; not a CI job)
- `test/staging` — End-to-end tests against live systems (shellchecked; not a CI job)

## Local Workflow Parity

- `./build` supports `--advice` (alias for `--advise`) and `--cache` for one-run scanner cache controls.
- `test/staging` supports `--scan`, `--no-scan`, `--advise`, and `--no-advise` for live-image validation.

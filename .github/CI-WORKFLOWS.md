# GitHub CI Workflows

Automated linting, building, testing, security scanning, and Docker image publication for pfsense-backup.

## Workflow Overview

| Stage          | Trigger                               | Purpose                                        |
| -------------- | ------------------------------------- | ---------------------------------------------- |
| **Lint**       | All pushes, PRs to main/master, tags  | Validate Dockerfile and shell scripts          |
| **Build**      | After lint                            | Build image and share as artifact              |
| **Tests**      | After build (6 jobs, parallel)        | Run each test suite independently              |
| **Scan**       | After build (parallel with tests)     | Trivy image scan — blocks push on fixable CVEs |
| **Push**       | Version tags and staging branch only  | Multi-platform build and push to Docker Hub    |
| **Dependabot**     | Weekly (Monday 06:00 UTC)             | Keep GitHub Actions versions current           |
| **Release Please** | Push to main/master                   | Open release PR; create tag and GitHub Release |

## CI Workflow (`ci.yml`)

Single unified workflow for all CI/CD stages.

### Global configuration

- **Image name:** `1121citrus/pfsense-backup`
- **Node.js actions runtime:** v24 (via `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24`)

### Trigger Events

- **Push:** `main`, `master`, `staging` branches and `v*` version tags
- **Pull requests:** `main`, `master` branches

### Concurrency

- **Group:** `<workflow-name>-<ref>` — one concurrent run per workflow + branch/tag
- **Branches and PRs:** Cancel any in-progress run when a newer one starts
- **Version tags:** Never cancelled — release builds always complete

### Versioning

Tag-driven. Push a git tag to publish a release:

```bash
git tag v1.2.3
git push origin v1.2.3
# Publishes: 1121citrus/pfsense-backup:1.2.3 + :1.2 + :1 + :latest
```

No automation bumps the version — the tag is always a deliberate decision.

---

## Stage 1: Lint

- **Hadolint** — Dockerfile best-practice checks
- **ShellCheck** — static analysis (`-x`) of `src/`, `test/`, and `build` scripts
  - Per-file `# shellcheck disable=SC1090` / `# shellcheck disable=SC1091` directives
    handle dynamic and install-time source paths inline

---

## Stage 2: Build

Builds image for `linux/amd64` (the runner's native platform) and exports as a gzip'd tarball (`/tmp/image.tar.gz`) uploaded as the `docker-image` artifact. The image is re-tagged as `:latest` so test scripts that default to `IMAGE:latest` work without modification. Each downstream job loads the image with `gunzip -c /tmp/image.tar.gz | docker load`.

Artifact retention: 1 day.

**Docker layer cache:** `cache-from: type=gha` / `cache-to: type=gha,mode=max` — build
layers are saved to and restored from GitHub Actions cache, speeding up incremental
builds. The push job restores from the same cache.

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
| Tag `v1.2.3`      | `1121citrus/pfsense-backup:1.2.3` + `:1.2` + `:1` + `:latest`  |
| Push to `staging` | `1121citrus/pfsense-backup:staging-<sha>` + `:staging`          |

- `:latest` is set **only** on version-tagged releases
- Staging uses a short commit SHA for traceability

### Build configuration

- **Platforms:** `linux/amd64`, `linux/arm64`
- **Attestations:** `sbom: true` + `provenance: mode=max` (SLSA L3)
- **Layer cache:** `cache-from: type=gha` / `cache-to: type=gha,mode=max`

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

## Automated dependency updates

`dependabot.yml` configures weekly automated PRs to keep GitHub Actions current.

- **Schedule:** Every Monday at 06:00 UTC
- **Scope:** GitHub Actions (`package-ecosystem: github-actions`) — updates action pins in
  `.github/workflows/*.yml`
- **Labels:** `dependencies`, `github-actions`
- **Security benefit:** Dependabot also proposes SHA-pinned digests (recommended for SLSA /
  OpenSSF Scorecard hardening)

---

## Local Workflow Parity

- `./build` supports `--advice` (alias for `--advise`) and `--cache` for one-run scanner cache controls.
- `test/staging` supports `--scan`, `--no-scan`, `--advise`, and `--no-advise` for live-image validation.

---

## Automated releases (release-please)

`release-please.yml` watches for [conventional commits](https://www.conventionalcommits.org/)
merged to `main`/`master` and automates the release lifecycle:

1. Opens a "release PR" that bumps `version.txt`, prepends to `CHANGELOG.md`, and proposes the next semver tag
2. When the release PR is merged, creates a GitHub Release and pushes the version tag
3. The existing CI `push` job fires on the new tag and builds and publishes the Docker image

### Conventional commit types that trigger version bumps

| Commit prefix | Bump |
|---|---|
| `fix:` | patch (1.0.x) |
| `feat:` | minor (1.x.0) |
| `feat!:` or `BREAKING CHANGE:` | major (x.0.0) |

All other prefixes (`ci:`, `docs:`, `chore:`, `refactor:`, `test:`, etc.) appear in the
changelog but do not trigger a version bump on their own.

### Configuration

- `release-please-config.json` — release type (`simple`) and package root
- `.release-please-manifest.json` — current version (updated by release-please on each release)
- `version.txt` — plain-text version file (updated by release-please; can be referenced in Dockerfile)
- `CHANGELOG.md` — generated/updated by release-please

# GitHub CI workflows

Automated linting, building, testing, security scanning, and Docker image publication
for pfsense-backup.

## Workflow overview

| Stage | Trigger | Purpose |
| ----- | ------- | ------- |
| **Lint** | All pushes, PRs to main/master, tags | Validate Dockerfile and shell scripts |
| **Build** | After lint | Build image and share as artifact |
| **Tests** | After build (8 jobs, parallel) | Run each test suite independently |
| **Scan** | After build (parallel with tests) | Trivy image scan — blocks push on fixable CVEs |
| **Push** | Version tags and staging branch only | Multi-platform build and push to Docker Hub |
| **Dependabot** | Weekly (Monday 06:00 UTC) | Keep GitHub Actions versions current |
| **Release Please** | Push to main/master | Open release PR; create tag and GitHub Release |

## CI workflow (`ci.yml`)

Lint, Build, Scan, and Push delegate to shared reusable workflows in
[1121citrus/shared-github-workflows](https://github.com/1121citrus/shared-github-workflows).
The 8 parallel test jobs are defined inline because they are specific to this repo.

### Global configuration

- **Image name:** `1121citrus/pfsense-backup`
- **Trivy ignore file:** `.trivyignore.yaml`

### Trigger events

- **Push:** `main`, `master`, `staging` branches and `v*` version tags
- **Pull requests:** To `main` or `master` branches

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

---

## Stage 1: Lint

Shared workflow: `lint.yml` — runs Hadolint, ShellCheck, and markdownlint-cli.

---

## Stage 2: Build

Shared workflow: `build.yml` — builds image and exports it as the `docker-image`
artifact. Re-tagged as `:latest`. Artifact retention: 1 day.

---

## Stage 3: Tests (parallel)

Eight inline jobs run simultaneously after build, each in its own `bats/bats:1.13.0`
container with the Docker socket mounted:

| Job | Test file | What it tests |
| --- | --------- | ------------- |
| `test-build` | `test/01-build.bats` | Image build assertions |
| `test-pfsense-backup` | `test/02-pfsense-backup.bats` | Core backup flow |
| `test-required-vars` | `test/03-backup-required-vars.bats` | Required environment variables |
| `test-backup-success` | `test/04-backup-success.bats` | Successful backup operation |
| `test-encryption` | `test/05-backup-encryption.bats` | Backup encryption |
| `test-aws-failure` | `test/06-backup-aws-failure.bats` | AWS upload error handling |
| `test-xml-validation` | `test/07-backup-xml-validation.bats` | pfSense XML config validity |
| `test-healthcheck` | `test/08-healthcheck.bats` | Container health check |

Each job downloads the shared artifact independently to maximize parallelism.

---

## Stage 4: Security scan

Shared workflow: `scan.yml` with `trivyignore: .trivyignore.yaml` — Trivy
CRITICAL/HIGH scan before push. Fails and blocks push on fixable CVEs.

---

## Stage 5: Push to Docker Hub

Shared workflow: `push.yml` — runs only when all 8 test jobs and the scan pass,
and only on version tags or the staging branch.

### Tagging

| Trigger | Docker Hub tags |
| ------- | --------------- |
| Tag `v1.2.3` | `1121citrus/pfsense-backup:1.2.3` + `:1.2` + `:1` + `:latest` |
| Push to `staging` | `1121citrus/pfsense-backup:staging-<sha>` + `:staging` |

### Build configuration

- **Platforms:** `linux/amd64`, `linux/arm64`
- **Attestations:** `sbom: true` + `provenance: mode=max` (SLSA L3)

---

## Execution flow

```text
On push/PR
    ↓
[Lint] — shared: hadolint + shellcheck + markdownlint
    ↓
[Build] — shared: single-arch image → artifact
    ↓ (parallel — 9 jobs)
[test-build]         [test-pfsense-backup]   [test-required-vars]
[test-backup-success][test-encryption]       [test-aws-failure]
[test-xml-validation][test-healthcheck]      [scan] — shared Trivy

[Push] (tags and staging only, after all 9 pass)
 - shared: QEMU + Buildx multi-arch
 - push amd64 + arm64
 - SBOM + provenance
```

---

## Configuration reference

### Required secrets

- `DOCKERHUB_USERNAME` — Docker Hub account
- `DOCKERHUB_TOKEN` — Docker Hub access token

### Key files

- `Dockerfile` — container build definition
- `build` — build helper script
- `src/backup` — main backup script
- `src/common-functions` — shared shell library
- `test/run-all` — test orchestrator
- `test/*.bats` — individual test suites
- `test/bin/` — mock binaries (aws, ssh, sshpass, traceroute)
- `.trivyignore.yaml` — CVE suppressions

## Automated dependency updates

`dependabot.yml` configures weekly automated PRs to keep GitHub Actions current.

---

## Automated releases (release-please)

`release-please.yml` delegates to the shared `release-please.yml` workflow.

### Configuration

- `release-please-config.json` — release type and package root
- `.release-please-manifest.json` — current version
- `version.txt` — plain-text version file
- `CHANGELOG.md` — generated/updated by release-please

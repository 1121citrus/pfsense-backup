# GitHub CI workflows

Automated linting, building, testing, security scanning, and Docker image publication
for pfsense-backup.

## Workflow overview

| Stage | Trigger | Purpose |
| ----- | ------- | ------- |
| **Lint** | All pushes, PRs to main/master, tags | Validate Dockerfile and shell scripts |
| **Build** | After lint | Build image and share as artifact |
| **Tests** | After build | Run all automated Bats suites in one job |
| **Scan** | After build (parallel with tests) | Trivy image scan — blocks push on fixable CVEs |
| **Push** | Version tags and staging branch only | Multi-platform build and push to Docker Hub |
| **Dependabot** | Weekly (Monday 06:00 UTC) | Keep GitHub Actions versions current |
| **Release Please** | Push to main/master | Open release PR; create tag and GitHub Release |

## CI workflow (`ci.yml`)

Lint, Build, Scan, and Push delegate to shared reusable workflows in
[1121citrus/shared-github-workflows](https://github.com/1121citrus/shared-github-workflows).
The repo-specific test job is defined inline because it loads the built image
artifact and runs the full Bats suite directly.

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

## Stage 3: Tests

One inline job runs after build inside `bats/bats:1.13.0` with the Docker
socket mounted. The job downloads the shared image artifact, loads it into the
local Docker daemon, and executes all automated suites:

| Suite | Test file | What it tests |
| --- | --------- | ------------- |
| `build` | `test/01-build.bats` | Image build assertions |
| `pfsense-backup` | `test/02-pfsense-backup.bats` | Core backup flow |
| `required-vars` | `test/03-backup-required-vars.bats` | Required environment variables |
| `backup-success` | `test/04-backup-success.bats` | Successful backup operation |
| `encryption` | `test/05-backup-encryption.bats` | Backup encryption |
| `aws-failure` | `test/06-backup-aws-failure.bats` | AWS upload error handling |
| `xml-validation` | `test/07-backup-xml-validation.bats` | pfSense XML config validity |
| `healthcheck` | `test/08-healthcheck.bats` | Container health check |
| `image-metadata` | `test/09-image-metadata.bats` | OCI label and build-arg wiring |
| `cli-flags` | `test/10-pfsense-backup-cli-flags.bats` | Extended CLI flag coverage |
| `scheduler-mode` | `test/11-scheduler-mode.bats` | Scheduler entry and handoff behavior |
| `multi-bucket` | `test/12-multi-bucket.bats` | Multi-bucket and dry-run behavior |

---

## Stage 4: Security scan

Shared workflow: `scan.yml` with `trivyignore: .trivyignore.yaml` — Trivy
CRITICAL/HIGH scan before push. Fails and blocks push on fixable CVEs.

---

## Stage 5: Push to Docker Hub

Shared workflow: `push.yml` — runs only when the test job and the scan pass,
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
    ↓ (parallel — 2 jobs)
[test] — Bats suites 01-12      [scan] — shared Trivy

[Push] (tags and staging only, after both pass)
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

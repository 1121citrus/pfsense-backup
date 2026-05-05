# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.7] - 2026-05-05

### Added

- Gitleaks CI workflow (`.github/workflows/gitleaks-ci.yml`) scans the
  repository for leaked secrets on every push and pull request
- `gitleaks` advisement in `build` script (`--advise gitleaks`, Stage 5e);
  non-gating, advisory only

### Changed

- Bump tool image versions in `build` and `test/staging`: `grype` v0.87.0 →
  v0.112.0, `trivy` 0.62.1 → 0.70.0, `hadolint` v2.12.0 → v2.14.0,
  `shellcheck` v0.10.0 → v0.11.0
- Filter small inefficient-file entries from Dive advisory output in
  `test/staging`; entries below `DIVE_MIN_WASTED_BYTES` (default 1 MB) are
  suppressed to reduce noise

## [1.0.6] - 2026-05-02

### Fixed

- Guard `s3api head-bucket` pre-flight with `! is_true "${DRYRUN:-false}"` so
  dryrun-only staging tests (`test_staging_backup_downloads_config`,
  `test_staging_backup_xml_has_expected_fields`) pass without live S3
  credentials; the bucket check is unnecessary before `aws s3 mv --dryrun`
- Populate `.trivyignore.yaml` with six AL2023 CVEs whose fix versions are
  identified by Trivy but not yet in the package repos — CVE-2026-4046
  (glibc), CVE-2026-3644/4224/4786/6100 (python3/cpython), CVE-2026-35385
  (openssh); fixes gating CI Trivy scan failure
- Mount `.trivyignore` into the Trivy container in `build` (Stage 4) and
  `test/staging` so locally suppressed CVEs are also suppressed in the
  local build pipeline
- Add `bats_require_minimum_version 1.5.0` to `test/13-source-coverage.bats`
  and convert three `run` calls to `run -127` to suppress BW02 warnings and
  assert the expected exec-failure exit code explicitly

## [1.0.5] - 2026-04-27

### Changed

- Migrate base image from Alpine to Amazon Linux 2023 (AL2023); replace
  `apk` with `dnf`; switch runtime packages to AL2023 equivalents
- Switch Dependabot schedule from weekly to daily

### Fixed

- Staging test: accept `DRYRUN` as alias for `AWS_DRYRUN` environment
  variable

## [1.0.4] - 2026-04-26

### Changed

- Bump `actions/checkout` v4 → v6.0.2 (addresses Dependabot PR #1)
- Bump `actions/download-artifact` v4 → v8.0.1 (addresses Dependabot PR #2)

## [1.0.3] - 2026-04-26

### Fixed

- `ci.yml` test job: mount Docker socket and install `docker-cli` so bats
  can run nested `docker run` calls (Docker-in-Docker via host socket).
  Mount source at `$PWD:$PWD` so nested volume paths resolve correctly on
  the host daemon; previously the `/code` alias broke inner volume mounts.

## [1.0.2] - 2026-04-26

### Fixed

- Remove `chmod +x test/bin/*` from `setup()` in 9 test files; the CI bats
  container mounts the repo read-only and `chmod` fails on a read-only
  filesystem. All `test/bin/` stubs are committed as `100755` so the call
  was redundant.

## [1.0.1] - 2026-04-25

### Fixed

- Bump supercronic v0.2.44 → v0.2.45 (Go ≥1.26.2); resolves CVE-2026-32280,
  CVE-2026-32281, CVE-2026-32282, CVE-2026-32283, CVE-2026-33810 (High)
- Add pip upgrade step: `cryptography≥46.0.5`, `urllib3≥2.6.3`,
  `wheel≥0.46.2`, `pip≥25.3`, `zipp≥3.19.1`; resolves CVE-2026-26007,
  CVE-2026-21441, CVE-2025-66471, CVE-2025-66418, CVE-2026-24049,
  CVE-2025-8869, CVE-2024-5569 (High/Medium)
- Trivy gating scan: 0 vulnerabilities

### Added

- `test/staging`: add `test_staging_cron_startup` — credential-free test
  that verifies the container stays running in scheduler mode and the
  crontab file is correctly written (catches Alpine `/var/spool/cron/crontabs`
  symlink permission bug)

### Removed

- `release-please.yml`, `.release-please-manifest.json`,
  `release-please-config.json` — versioning done by hand

### Changed

- Pin `shared-github-workflows` CI ref from `@main` to `@v1`
- Clear `.trivyignore` and `.trivyignore.yaml` — all previously suppressed
  CVEs are now fixed upstream
- Rewrite `SECURITY.md` with current CVE status tables

## [0.0.2] - 2025-03-25

### Added

- Initial release

[Unreleased]: https://github.com/1121citrus/pfsense-backup/compare/v1.0.7...HEAD
[1.0.7]: https://github.com/1121citrus/pfsense-backup/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/1121citrus/pfsense-backup/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/1121citrus/pfsense-backup/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/1121citrus/pfsense-backup/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/1121citrus/pfsense-backup/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/1121citrus/pfsense-backup/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/1121citrus/pfsense-backup/compare/v0.0.2...v1.0.1
[0.0.2]: https://github.com/1121citrus/pfsense-backup/releases/tag/v0.0.2

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/1121citrus/pfsense-backup/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/1121citrus/pfsense-backup/compare/v0.0.2...v1.0.1
[0.0.2]: https://github.com/1121citrus/pfsense-backup/releases/tag/v0.0.2

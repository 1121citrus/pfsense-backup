# src — script reference

Scripts installed into the container image.

---

## Script inventory

| Script | Role | Entry point |
|---|---|---|
| `pfsense-backup` | **Primary CLI** — SSH into pfSense, download the config XML, stream to stdout | user / direct invocation |
| `backup` | **Legacy service** — calls `pfsense-backup`, compresses, encrypts, uploads to S3, touches healthcheck marker | user / cron |
| `startup` | Container entrypoint — writes `.env`, installs crontab, touches startup marker, hands off to `crond` | `CMD` in Dockerfile |
| `healthcheck` | Docker `HEALTHCHECK` — verifies `crond` is running, crontab is configured, and a recent backup succeeded | Docker daemon |
| `common-functions` | Shared logging helpers (`info`, `error`, `debug`, etc.) — sourced by the other scripts | sourced library |

---

## Data flow

### CLI mode (primary)

```
docker run ... pfsense-backup > config.xml
  └─ pfsense-backup
        └─ sshpass → ssh → pfSense host
              → config.xml download → stdout
```

### Service mode (legacy)

```
Docker CMD
  └─ startup
        └─ crond (daemon, PID 1)
              └─ backup  (on CRON_EXPRESSION schedule)
                    └─ pfsense-backup → config.xml download → stdout
                    └─ compress  (bzip2 / gzip / xz / …, stdin→stdout)
                    └─ gpg --symmetric  (optional)
                    └─ aws s3 mv  →  S3 bucket
                    └─ touch HEALTHCHECK_SUCCESS_FILE
```

---

## `pfsense-backup`

The primary script.  Connects to a pfSense firewall via SSH, downloads
`config.xml`, validates required XML fields, writes the suggested output
filename to `PFSENSE_BACKUP_NAME_FILE` (sidecar, optional), and streams
the raw XML to stdout.  All progress messages go to stderr.

### SSH approach

pfSense supports public-key authentication, but the key itself requires a
passphrase.  `sshpass` supplies the passphrase non-interactively; `ssh`
handles the actual connection.  This avoids the complexity of `expect`
while still automating a passphrase-protected key.

### SSH flags

| Flag / option | Reason |
|---|---|
| `-F /dev/null` | Ignore `~/.ssh/config`; prevent local settings from interfering |
| `-T` | No PTY; the backup user runs a command, not an interactive shell |
| `LogLevel=quiet` | Suppress banner / MOTD noise on stdout |
| `StrictHostKeyChecking=accept-new` | Trust on first connect, reject changed keys thereafter |
| `UserKnownHostsFile` | Persist known hosts across runs; redirect to `/dev/null` only when strict checking is disabled |

### `sshpass` flags

| Flag | Reason |
|---|---|
| `-P passphrase` | Match the key-passphrase prompt string (not the login password prompt) |
| `-p VALUE` | Pass passphrase inline — briefly visible in `/proc/<pid>/cmdline` |
| `-f FILE` | Read passphrase from file — never appears in the process table; preferred for production |

### Host resolution

Priority order: `--host` CLI flag → `PFSENSE_HOST` → `TAILSCALE_HOST` →
first hop of `traceroute -m 1 1.1.1.1`.  The traceroute fallback is a
last-resort for bare-metal / VM deployments where the firewall is the
default gateway.

### XML validation

Validates that the downloaded content contains `<version>` and
`<hostname>` elements.  Errors if either is missing, preventing a silent
authentication failure (where pfSense returns an error page instead of
XML) from propagating as a corrupt backup.

### Filename sanitization

Values extracted from the XML (`hostname`, `version`) are restricted to
`[a-zA-Z0-9._-]` before embedding in the filename.  Any other character
is replaced with a hyphen to prevent directory traversal and filename
injection via a crafted config file.

### `PFSENSE_BACKUP_NAME_FILE` sidecar

If set, `pfsense-backup` writes the computed filename (e.g.
`20251020T030000-firewall-pfsense-v24.11-config-backup.xml`) to this
path.  The `backup` service uses this to name the output file without
re-parsing the XML stream.

---

## `backup`

Legacy service wrapper.  Calls `pfsense-backup` using the
`PFSENSE_BACKUP_NAME_FILE` sidecar, adds a header comment to the
downloaded XML, optionally compresses and encrypts, uploads to S3, and
touches a healthcheck sentinel file on success.

### Compression ordering

All compression is stdin→stdout to avoid creating additional copies of
the XML file in the workdir.  Compression runs before encryption so that
GPG operates on already-reduced data.

### `aws s3 mv` (not `cp`)

`mv` uploads and then deletes the local copy on success, preventing
archives from accumulating in the workdir across successive cron runs.

### Healthcheck marker ordering

`HEALTHCHECK_SUCCESS_FILE` is touched only after a confirmed successful
`aws s3 mv`.  It is never touched before the upload or on any failure
path.

---

## `startup`

Container entrypoint for service mode.  Writes all runtime configuration
to `~/.env` (the file that `crond` jobs source at startup), installs the
crontab entry, touches the startup marker, and execs `crond -f` as PID 1.

### `.env` write-and-source pattern

crond runs jobs with a minimal environment.  Writing configuration to a
file that each job sources is simpler and more reliable than threading
environment variables through crond's own `ENVFILE` mechanism.

### `__quote` helper

Handles embedded single quotes in variable values via the standard shell
quoting idiom (`'` → `'"'"'`), keeping the generated `export` statements
syntactically valid when sourced.

### `HEALTHCHECK_STARTUP_FILE`

Touched immediately before handing off to crond.  The healthcheck uses
this marker to distinguish a freshly started container (within startup
grace window — healthy) from one where the cron job is genuinely overdue.

---

## `healthcheck`

Checks three conditions:

1. **crontab configured** — `/var/spool/cron/crontabs/root` exists and
   contains the `/usr/local/bin/backup` entry.
2. **crond running** — `pidof crond` with `pgrep -x crond` fallback for
   portability across busybox and procps variants.
3. **backup ran recently** — dual-marker age-based check (see below).

### Dual-marker health check

Uses two sentinel files:

| Marker | Written by | Meaning |
|---|---|---|
| `HEALTHCHECK_SUCCESS_FILE` | `backup` (after successful S3 upload) | When did the last good backup complete? |
| `HEALTHCHECK_STARTUP_FILE` | `startup` (before crond is exec'd) | When did this container instance start? |

Both markers are evaluated independently before any error is emitted.
This correctly handles a container restart where a stale success marker
survives on a persistent volume: the startup file is fresh, so the grace
window applies and the container is reported healthy until a new backup
runs.

### `epoch_modified`

Returns a file's modification time as Unix epoch seconds.  GNU
`stat -c %Y` (Linux / Alpine) is tried first; BSD `stat -f %m` (macOS)
is the fallback.

---

## Adding a new compression algorithm

1. Add a new `case` branch in `backup` following the existing pattern.
2. Choose a stdin→stdout invocation to avoid a redundant temp file.
3. Update the `COMPRESSION` description in `README.md` (project root).
4. Add test coverage in `test/backup-success`.

## Adding a new CLI option to `pfsense-backup`

1. Add the long / short option to the `while` loop option parser.
2. Add the corresponding env-var default before the loop.
3. Update the `show_help()` function and the header comment block.
4. Document the env var in the main `README.md` environment-variable
   table.
5. Add test coverage in `test/pfsense-backup`.

## Adding a new environment variable (service mode)

1. Add the variable with its default to `startup` (the `.env` write
   block).
2. Document it in the main `README.md` environment-variable table.
3. If it affects backup behavior, add a test case in the appropriate
   `test/backup-*` file.

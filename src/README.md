# src — script reference

Scripts installed into the container image.

---

## Script inventory

| Script | Role | Entry point |
|---|---|---|
| `pfsense-backup` | **Primary CLI** — SSH into pfSense, download the config XML, stream to stdout | user / direct invocation |
| `backup` | Compatibility wrapper and image `CMD` — requires a bucket option/env and then execs `pfsense-backup` for one-shot S3 upload | user / default `CMD` |
| `startup` | Compatibility wrapper for older deployments — execs `pfsense-backup --cron` | explicit entrypoint override |
| `healthcheck` | Docker `HEALTHCHECK` — verifies `supercronic` is running, the schedule file is configured, and a recent backup succeeded | Docker daemon |
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

### Scheduler mode

```
docker run ... /usr/local/bin/pfsense-backup --cron
  └─ pfsense-backup run_scheduler()
     └─ write ~/.env + crontab file
     └─ exec supercronic (PID 1)
        └─ pfsense-backup  (on CRON_EXPRESSION schedule)
           └─ config.xml download
           └─ compress  (optional)
           └─ gpg --symmetric  (optional)
           └─ aws s3 mv  →  each bucket in BUCKET_LIST
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

Compatibility wrapper retained for existing deployments and for the image
default `CMD`. It performs only two tasks:

1. Validate that a bucket was supplied via `AWS_S3_BUCKET_NAME`, `BUCKET`,
   `BUCKET_LIST`, `--bucket`, or `--bucket-list`.
2. Exec `pfsense-backup` with `PFSENSE_BACKUP_COMMAND=backup` so log lines
   still identify the wrapper invocation.

All download, compression, encryption, upload, and healthcheck-marker logic
now lives in `pfsense-backup` itself.

---

## `startup`

Compatibility shim. Older deployments may still set
`entrypoint: /usr/local/bin/startup`; the script now immediately execs
`pfsense-backup --cron`.

New deployments should invoke `pfsense-backup --cron` directly.

---

## `healthcheck`

Checks three conditions:

1. **crontab configured** — `/var/spool/cron/crontabs/$(id -un)` exists and
   contains the scheduled `pfsense-backup` entry.
2. **supercronic running** — `pgrep -x supercronic` confirms the scheduler
   process is alive.
3. **backup ran recently** — dual-marker age-based check (see below).

### Dual-marker health check

Uses two sentinel files:

| Marker | Written by | Meaning |
|---|---|---|
| `HEALTHCHECK_SUCCESS_FILE` | `pfsense-backup` (after successful S3 upload) | When did the last good backup complete? |
| `HEALTHCHECK_STARTUP_FILE` | `pfsense-backup` scheduler mode (before `supercronic` is exec'd) | When did this scheduler instance start? |

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

1. Add a new `case` branch in `pfsense-backup` following the existing pattern.
2. Choose a stdin→stdout invocation to avoid a redundant temp file.
3. Update the `COMPRESSION` description in `README.md` (project root).
4. Add test coverage in `test/04-backup-success.bats`.

## Adding a new CLI option to `pfsense-backup`

1. Add the long / short option to the `while` loop option parser.
2. Add the corresponding env-var default before the loop.
3. Update the `show_help()` function and the header comment block.
4. Document the env var in the main `README.md` environment-variable
   table.
5. Add test coverage in the appropriate CLI suite, typically
   `test/02-pfsense-backup.bats` or `test/10-pfsense-backup-cli-flags.bats`.

## Adding a new environment variable (service mode)

1. Add the variable with its default to `pfsense-backup` and, if scheduler
   mode needs it, to `create_environment()`.
2. Document it in the main `README.md` environment-variable table.
3. If it affects backup behavior, add a test case in the appropriate
   numbered `.bats` file under `test/`.

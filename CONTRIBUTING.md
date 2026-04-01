# Contributing

## Prerequisites

- Docker with buildx support
- Bash 4.0+
- A pfSense instance for integration testing (optional but recommended)

## Development Workflow

### Building

The `build` script runs the enabled stages in order: lint → build → test →
scan → advise → push.

```bash
./build              # Local build and test
./build --push       # Push to Docker Hub
./build --help       # See all options
```

### Testing

Run the test suite against a locally built image:

```bash
./build --no-scan
```

Or manually:

```bash
docker buildx build --load -t 1121citrus/pfsense-backup:test .
IMAGE=1121citrus/pfsense-backup:test ./test/run-all
```

### Code Style

The canonical lint path is `./build`, which already runs Hadolint,
ShellCheck, and markdownlint. If a manual run is needed, use the same file
set as the build script:

```bash
hadolint Dockerfile
shellcheck build src/backup src/common-functions src/healthcheck \
    src/pfsense-backup src/startup test/run-all test/staging \
    test/bin/aws test/bin/ssh test/bin/sshpass test/bin/traceroute
markdownlint "**/*.md"
```

The `./build` stage runs these automatically.

### Submitting Changes

1. Create a topic branch from `master`
2. Make your changes
3. Run `./build` to lint, test, and scan
4. Submit a pull request to the `master` branch

## Release Process

Releases are tagged with semantic versions:

```bash
./build --push --version 1.2.3
```

Tags trigger a multi-platform build and push to Docker Hub, plus SLSA provenance and SBOM generation.

# syntax=docker/dockerfile:1

# An application specific service to create pfSense backups and copy them off site.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

# aws-backup-base 1.2.3 (AL2023 2023.12.20261112, supercronic v0.2.49 built
# with Go 1.27.4), pinned by multi-arch index digest.
ARG BASE_IMAGE=1121citrus/aws-backup-base@sha256:dc4c176e47b9d1b818c149466bcb61ed2e5ea643a0d947d6b8fc8519b2b14852

ARG PFSENSE_BACKUP_VERSION=
ARG VERSION=dev

# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Re-declare build args after FROM so they are visible in the build stage.
ARG VERSION
ENV VERSION=${VERSION}

ARG BUILD_DATE=unknown
ENV BUILD_DATE=${BUILD_DATE}

ARG GIT_COMMIT=unknown
ENV GIT_COMMIT=${GIT_COMMIT}

ARG PFSENSE_BACKUP_VERSION
ENV PFSENSE_BACKUP_VERSION=${PFSENSE_BACKUP_VERSION:-${VERSION}}

# Create a non-privileged user; grant ownership of runtime-writable paths.
ARG UID=10001
ENV UID=${UID}

ARG GID=10001
ENV GID=${GID}

ARG USERNAME=pfsense-backup
ENV USERNAME=${USERNAME}

# OCI image annotations (https://github.com/opencontainers/image-spec/blob/main/annotations.md)
LABEL org.opencontainers.image.title="pfsense-backup" \
      org.opencontainers.image.description="Periodic pfSense configuration backup to AWS S3" \
      org.opencontainers.image.url="https://github.com/1121citrus/pfsense-backup" \
      org.opencontainers.image.source="https://github.com/1121citrus/pfsense-backup" \
      org.opencontainers.image.vendor="1121 Citrus Avenue" \
      org.opencontainers.image.authors="1121-citrus <1121-citrus@gmail.com>" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}"

# Install dependencies and configure the container environment.
# bzip3 and pixz are not available in AL2023; gzip, bzip2, xz, lzop, and pigz
# cover all common backup compression scenarios.
# AL2023 locks dnf to the base image's release version, so a plain
# `dnf upgrade` cannot reach security fixes published after the base image
# was built.  `--releasever=latest` resolves against the newest AL2023
# repository snapshot so every installed package picks up current fixes.
#
# No pip packages are installed: `/usr/bin/aws` runs as `python3 -s`, so
# it never sees `/usr/local`, and no script here runs `python3`. A pip copy
# of urllib3 would only add findings that no code path uses. perl is also
# unused and removed. python3-setuptools is removed with `rpm -e --nodeps`:
# awscli-2 requires it through python3-ruamel-yaml, so `dnf remove` would
# take the AWS CLI too. `aws --version` fails the build if the CLI is gone.
# hadolint ignore=DL3041
RUN set -eux; \
    dnf install -y --quiet --releasever=latest \
        bzip2 \
        gnupg2 \
        gzip \
        lzop \
        openssh-clients \
        openssl \
        pigz \
        sshpass \
        traceroute \
        xz \
        zip \
    && dnf upgrade -y --quiet --releasever=latest \
    && dnf remove -y --quiet 'perl*' \
    && rpm -e --nodeps \
            python3-setuptools \
            python3-setuptools-wheel \
            python3-pip-wheel \
    && aws --version \
    && install -d -m 755 \
            /usr/local/share/pfsense-backup \
            /var/log/pfsense-backup \
    && touch /var/log/pfsense-backup/pfsense-backup.log \
    && mkdir -pv "/${USERNAME}/.gnupg" "/${USERNAME}/.ssh" \
    && chmod 700 "/${USERNAME}/.gnupg" "/${USERNAME}/.ssh" \
    && touch "/${USERNAME}/.gnupg/pubring.kbx" \
    && chmod 600 "/${USERNAME}/.gnupg/pubring.kbx" \
    && ln -sfv /run/secrets/pfsense-identity "/${USERNAME}/.ssh/pfsense-identity" \
    && printf '%s\n' "${VERSION}" > /usr/local/share/pfsense-backup/version \
    && printf '%s\n' "${GIT_COMMIT}" > /usr/local/share/pfsense-backup/git-commit \
    && printf '%s\n' "${BUILD_DATE}" > /usr/local/share/pfsense-backup/build-date \
    && dnf clean all \
    && rm -rf /var/cache/dnf \
    && echo "[INFO] completed installing pfsense-backup"

COPY --chmod=755 ./src/healthcheck ./src/backup ./src/pfsense-backup \
                 ./src/startup /usr/local/bin/
COPY --chmod=644 ./include/logging ./include/path /usr/local/include/

RUN groupadd --gid "${GID}" "${USERNAME}" \
    && useradd \
        --no-create-home --shell /sbin/nologin \
        --home "/${USERNAME}" \
        --uid "${UID}" --gid "${GID}" "${USERNAME}" \
    && install -d -m 755 /var/spool/cron \
    && install -d -m 0755 -o "${USERNAME}" /var/spool/cron/crontabs \
    && chown -R "${USERNAME}" "/${USERNAME}" \
    && chown "${USERNAME}" /var/log/pfsense-backup /var/log/pfsense-backup/pfsense-backup.log

USER "${USERNAME}"

HEALTHCHECK --interval=60s --timeout=5s --retries=3 CMD ["/usr/local/bin/healthcheck"]

WORKDIR /

CMD ["/usr/local/bin/backup"]

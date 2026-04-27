# syntax=docker/dockerfile:1

# An application specific service to create pfSense backups and copy them off site.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

ARG BASE_IMAGE=1121citrus/aws-backup-base:latest

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
# hadolint ignore=DL3041
RUN set -eux; \
    dnf install -y --quiet \
        bzip2 \
        gnupg2 \
        gzip \
        lzop \
        openssh-clients \
        openssl \
        pigz \
        python3-pip \
        sshpass \
        traceroute \
        xz \
        zip \
    && pip3 install --no-cache-dir --upgrade \
        'cryptography>=46.0.5' \
        'urllib3>=2.6.3' \
        'wheel>=0.46.2' \
        'zipp>=3.19.1' \
    && dnf reinstall -y --quiet python3-urllib3 \
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

COPY --chmod=644 ./src/common-functions /usr/local/include/
COPY --chmod=755 ./src/healthcheck ./src/backup ./src/pfsense-backup \
                 ./src/startup /usr/local/bin/

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

# syntax=docker/dockerfile:1

# An application specific service to create pfSense backups and copy them off site.
#
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Alpine 3.22
ARG ALPINE_IMAGE_DIGEST=sha256:55ae5d250caebc548793f321534bc6a8ef1d116f334f18f4ada1b2daad3251b2
ARG ALPINE_VERSION=alpine@${ALPINE_IMAGE_DIGEST}

ARG PFSENSE_BACKUP_VERSION=
# ARG PYTHON_VERSION=3.12
ARG SUPERCRONIC_VERSION=v0.2.44
ARG VERSION=dev

# hadolint ignore=DL3006
FROM ${ALPINE_VERSION}
# FROM python:${PYTHON_VERSION}-alpine${ALPINE_VERSION}

# Re-declare build args after FROM so they are visible in the build stage.
ARG VERSION
ENV VERSION=${VERSION}

ARG ALPINE_IMAGE_DIGEST
ENV ALPINE_IMAGE_DIGEST=${ALPINE_IMAGE_DIGEST}

ARG ALPINE_VERSION
ENV ALPINE_VERSION=${ALPINE_VERSION}

ARG BUILD_DATE=unknown
ENV BUILD_DATE=${BUILD_DATE}

ARG GIT_COMMIT=unknown
ENV GIT_COMMIT=${GIT_COMMIT}

ARG PFSENSE_BACKUP_VERSION
ENV PFSENSE_BACKUP_VERSION=${PFSENSE_BACKUP_VERSION:-${VERSION}}

# ARG PYTHON_VERSION
# ENV PYTHON_VERSION=${PYTHON_VERSION}

ARG SUPERCRONIC_VERSION
ENV SUPERCRONIC_VERSION=${SUPERCRONIC_VERSION}

# Create a non-privileged user; grant ownership of runtime-writable paths.
ARG UID=10001
ENV UID=${UID}

ARG GID=10001
ENV GID=${GID}

ARG USERNAME=pfsense-backup
ENV USERNAME=${USERNAME}

# OCI image annotations (https://github.com/opencontainers/image-spec/blob/main/annotations.md)
# These are embedded in the image manifest and surfaced by `docker inspect`,
# `docker buildx imagetools inspect`, and registry UIs.
LABEL org.opencontainers.image.title="pfsense-backup" \
      org.opencontainers.image.description="Periodic pfSense configuration backup to AWS S3" \
      org.opencontainers.image.url="https://github.com/1121citrus/pfsense-backup" \
      org.opencontainers.image.source="https://github.com/1121citrus/pfsense-backup" \
      org.opencontainers.image.vendor="1121 Citrus Avenue" \
      org.opencontainers.image.authors="1121-citrus <1121-citrus@gmail.com>" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="alpine:${ALPINE_VERSION}" \
      org.opencontainers.image.base.digest="${ALPINE_IMAGE_DIGEST}" \
      org.opencontainers.image.runtime="docker" \
      org.opencontainers.image.build.cmd="docker build --build-arg VERSION=${VERSION} --build-arg ALPINE_VERSION=${ALPINE_VERSION} --build-arg PFSENSE_BACKUP_VERSION=${PFSENSE_BACKUP_VERSION} --build-arg SUPERCRONIC_VERSION=${SUPERCRONIC_VERSION} --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') --build-arg GIT_COMMIT=$(git rev-parse --short HEAD) -t pfsense-backup:${VERSION} ."

# Install dependencies and configure the container environment.
# DL3018: version constraints use '>' (minimum) rather than '=' (exact) by
# design — apk does not have a lock-file mechanism and exact pins would break
# on every Alpine point release.
# hadolint ignore=DL3018,DL4006
RUN set -eux; \
    apk update && \
    apk upgrade --no-cache --no-interactive && \
    apk add --no-cache --no-interactive --upgrade \
        'aws-cli>2.20' \
        'bash>5.2' \
        'bzip2>1.0' \
        'bzip3>1.3' \
        'gnupg>2.4' \
        'gzip>1.12' \
        'lzop>1.04' \
        'openssh>9' \
        'openssl>3.3' \
        'pigz>2.8' \
        'pixz>1.0' \
        'sshpass>1.10' \
        'traceroute>2.1' \
        'xz>5.6' \
        'zip>3.0' \
    && echo "[INFO] installing supercronic ${SUPERCRONIC_VERSION}" \
    && SUPERCRONIC_ARCH="$(uname -m \
            | sed 's/x86_64/amd64/;s/aarch64/arm64/')" \
    && wget -qO /usr/local/bin/supercronic \
            "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${SUPERCRONIC_ARCH}" \
    && chmod 0755 /usr/local/bin/supercronic \
    && install -d -m 755 \
            /usr/local/include \
            /usr/local/share/pfsense-backup \
            /var/log/pfsense-backup \
    && touch /var/log/pfsense-backup/pfsense-backup.log \
    && printf '%s\n' "${VERSION}" \
            > /usr/local/share/pfsense-backup/version \
    && echo "[INFO] completed installing pfsense-backup" \
    && mkdir -pv /${USERNAME}/.gnupg /${USERNAME}/.ssh \
    && chmod 700 /${USERNAME}/.gnupg /${USERNAME}/.ssh \
    && touch /${USERNAME}/.gnupg/pubring.kbx \
    && chmod 600 /${USERNAME}/.gnupg/pubring.kbx \
    && rm -fv /usr/${USERNAME}/bin/docker /usr/bin/docker /bin/docker || true \
    && ln -sfv /run/secrets/pfsense-identity /${USERNAME}/.ssh/pfsense-identity \
    && mkdir --parents /usr/local/share/pfsense-backup \
    && printf '%s\n' "${VERSION}" > /usr/local/share/pfsense-backup/version \
    && printf '%s\n' "${GIT_COMMIT}" > /usr/local/share/pfsense-backup/git-commit \
    && printf '%s\n' "${BUILD_DATE}" > /usr/local/share/pfsense-backup/build-date \
    && echo "[INFO] completed installing pfsense-backup" \
    && true

COPY --chmod=644 ./src/common-functions /usr/local/include/
COPY --chmod=755 ./src/healthcheck ./src/backup ./src/pfsense-backup \
                 ./src/startup /usr/local/bin/

RUN addgroup --gid "${GID}" "${USERNAME}" \
    && adduser \
        --disabled-password --gecos "" --shell "/sbin/nologin" \
        --home "/${USERNAME}" \
        --uid "${UID}" --ingroup "${USERNAME}" "${USERNAME}" \
    && rm -f /var/spool/cron/crontabs \
    && install -d -m 0755 -o "${USERNAME}" /var/spool/cron/crontabs \
    && chown -R "${USERNAME}" "/${USERNAME}" \
    && chown "${USERNAME}" /var/log/pfsense-backup /var/log/pfsense-backup/pfsense-backup.log \
    && true

USER "${USERNAME}" 

HEALTHCHECK --interval=60s --timeout=5s --retries=3 CMD ["/usr/local/bin/healthcheck"]

WORKDIR /

CMD ["/usr/local/bin/backup"]

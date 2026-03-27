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

ARG ALPINE_TAG=3.22
FROM alpine:${ALPINE_TAG}

ARG VERSION=dev
ARG GIT_COMMIT=unknown
ARG BUILD_DATE=unknown

# OCI image annotations (https://github.com/opencontainers/image-spec/blob/main/annotations.md)
# These are embedded in the image manifest and surfaced by `docker inspect`,
# `docker buildx imagetools inspect`, and registry UIs.
LABEL org.opencontainers.image.title="pfsense-backup" \
      org.opencontainers.image.description="Periodic pfSense configuration backup to AWS S3" \
      org.opencontainers.image.url="https://github.com/1121citrus/pfsense-backup" \
      org.opencontainers.image.source="https://github.com/1121citrus/pfsense-backup" \
      org.opencontainers.image.vendor="1121 Citrus Avenue" \
      org.opencontainers.image.authors="James Hanlon <jim@hanlonsoftware.com>" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}"

# Install dependencies and configure the container environment.
# DL3018: version constraints use '>' (minimum) rather than '=' (exact) by
# design — apk does not have a lock-file mechanism and exact pins would break
# on every Alpine point release.
# hadolint ignore=DL3018
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
        && \
    mkdir -pv /root/.gnupg /root/.ssh && \
    chmod 700 /root/.gnupg /root/.ssh && \
    touch /root/.gnupg/pubring.kbx && \
    chmod 600 /root/.gnupg/pubring.kbx && \
    rm -fv /usr/local/bin/docker /usr/bin/docker /bin/docker || true && \
    ln -sfv /run/secrets/pfsense-identity /root/.ssh/pfsense-identity && \
    mkdir --parents --verbose /usr/local/1121citrus/bin && \
    chmod 755 /usr/local/1121citrus/bin && \
    mkdir --parents /usr/local/share/pfsense-backup && \
    printf '%s\n' "${VERSION}" > /usr/local/share/pfsense-backup/version && \
    true

COPY --chmod=755 ./src/startup /usr/local/1121citrus/bin
COPY --chmod=755 \
    ./src/backup \
    ./src/common-functions \
    ./src/healthcheck \
    ./src/pfsense-backup \
    /usr/local/bin/

HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD /usr/local/bin/healthcheck

CMD [ "/usr/local/1121citrus/bin/startup" ]


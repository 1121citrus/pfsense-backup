#!/usr/bin/env bash
# shellcheck shell=bash

# Prepend /test/bin to PATH when the test stub directory is mounted.
# Sourced by /etc/profile (via /etc/profile.d/) on every bash invocation inside
# the container, including subprocesses started by the backup script.
if [[ -d /test/bin ]]; then
  export PATH="/test/bin:${PATH}"
fi

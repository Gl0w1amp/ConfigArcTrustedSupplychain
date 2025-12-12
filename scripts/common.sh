#!/usr/bin/env bash
# Shared helpers for pipeline scripts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
TMP_DIR="$(mktemp -d)"

cleanup() {
  if [[ -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

log() {
  local level="$1"; shift
  printf '[%s] %s\n' "${level}" "$*" >&2
}

log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    log_error "Required environment variable ${name} is not set"
    exit 1
  fi
}

ensure_dist() {
  mkdir -p "${DIST_DIR}"
}

iso_utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

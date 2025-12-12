#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

require_env R2_ACCOUNT_ID
require_env R2_ACCESS_KEY_ID
require_env R2_SECRET_ACCESS_KEY
require_env R2_BUCKET

MANIFEST_PATH="${DIST_DIR}/manifest.json"
MANIFEST_SIG_PATH="${DIST_DIR}/manifest.json.minisig"

if [[ ! -f "${MANIFEST_PATH}" || ! -f "${MANIFEST_SIG_PATH}" ]]; then
  log_error "Manifest or its signature is missing. Run signing steps first."
  exit 1
fi

AWS_DEFAULT_REGION="auto"
export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION

ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"

artifact_lines="$(jq -r '.artifacts[] | [.name, .r2_key, .minisig.r2_key] | @tsv' "${MANIFEST_PATH}")"
if [[ -z "${artifact_lines}" ]]; then
  log_error "No artifacts found in manifest."
  exit 1
fi

upload_object() {
  local src="$1"
  local dest_key="$2"
  aws s3 cp "${src}" "s3://${R2_BUCKET}/${dest_key}" --endpoint-url "${ENDPOINT}"
}

log_info "Uploading versioned objects to s3://${R2_BUCKET}"
while IFS=$'\t' read -r name key sig_key; do
  local_path="${DIST_DIR}/${name}"
  if [[ ! -f "${local_path}" ]]; then
    local_path="${DIST_DIR}/components/${name}"
  fi
  if [[ ! -f "${local_path}" ]]; then
    log_error "Local artifact not found for ${name}"
    exit 1
  fi
  sig_path="${local_path}.minisig"
  if [[ ! -f "${sig_path}" ]]; then
    log_error "Signature missing for ${name}"
    exit 1
  fi
  upload_object "${local_path}" "${key}"
  upload_object "${sig_path}" "${sig_key}"
done <<< "${artifact_lines}"

manifest_key="$(jq -r '.r2.manifest.r2_key' "${MANIFEST_PATH}")"
manifest_sig_key="$(jq -r '.r2.manifest_sig.r2_key' "${MANIFEST_PATH}")"
latest_manifest_key="$(jq -r '.r2.latest.manifest.r2_key' "${MANIFEST_PATH}")"
latest_manifest_sig_key="$(jq -r '.r2.latest.manifest_sig.r2_key' "${MANIFEST_PATH}")"

upload_object "${MANIFEST_PATH}" "${manifest_key}"
upload_object "${MANIFEST_SIG_PATH}" "${manifest_sig_key}"

log_info "Updating latest manifest pointers"
upload_object "${MANIFEST_PATH}" "${latest_manifest_key}"
upload_object "${MANIFEST_SIG_PATH}" "${latest_manifest_sig_key}"

log_info "Uploaded keys:"
printf ' - %s\n' \
  $(jq -r '.artifacts[].r2_key' "${MANIFEST_PATH}") \
  $(jq -r '.artifacts[].minisig.r2_key' "${MANIFEST_PATH}") \
  "${manifest_key}" \
  "${manifest_sig_key}" \
  "${latest_manifest_key}" \
  "${latest_manifest_sig_key}"

if [[ -n "${R2_PUBLIC_BASE_URL:-}" ]]; then
  base="${R2_PUBLIC_BASE_URL%/}"
  printf 'Public URLs:\n'
  printf ' - %s/%s\n' "${base}" "${latest_manifest_key}"
  printf ' - %s/%s\n' "${base}" "${latest_manifest_sig_key}"
else
  log_info "Endpoint: ${ENDPOINT}"
  log_info "Latest manifest key: ${latest_manifest_key}"
fi

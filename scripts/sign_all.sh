#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

require_env MINISIGN_SECRET_KEY_B64

META_FILE="${DIST_DIR}/upstream_meta.json"
if [[ ! -f "${META_FILE}" ]]; then
  log_error "Missing ${META_FILE}. Run scripts/fetch_upstream.sh first."
  exit 1
fi

artifact_name="$(jq -r '.asset_name' "${META_FILE}")"
artifact_path="${DIST_DIR}/${artifact_name}"
artifact_sig_path="${artifact_path}.minisig"

if [[ ! -f "${artifact_path}" ]]; then
  log_error "Artifact ${artifact_path} not found. Run scripts/fetch_upstream.sh."
  exit 1
fi

secret_key_file="$(mktemp)"
log_info "Decoding minisign secret key to ${secret_key_file}"
printf '%s' "${MINISIGN_SECRET_KEY_B64}" | base64 --decode > "${secret_key_file}"
chmod 600 "${secret_key_file}"

log_info "Signing artifact ${artifact_path}"
minisign -Sm "${artifact_path}" -s "${secret_key_file}" -x "${artifact_sig_path}"

components_index="${DIST_DIR}/components/index.json"
component_names=()
if [[ "${SPLIT_INNER_ZIPS:-1}" == "1" && -f "${components_index}" ]]; then
  mapfile -t component_names < <(jq -r '.[].name' "${components_index}")
fi

for comp_name in "${component_names[@]}"; do
  comp_path="${DIST_DIR}/components/${comp_name}"
  if [[ ! -f "${comp_path}" ]]; then
    log_warn "Component ${comp_path} missing; skipping signature."
    continue
  fi
  log_info "Signing component ${comp_path}"
  minisign -Sm "${comp_path}" -s "${secret_key_file}" -x "${comp_path}.minisig"
done

log_info "Regenerating manifest to include signature metadata"
EXPECT_SIGNATURES=1 bash "${SCRIPT_DIR}/generate_manifest.sh"

log_info "Collecting file hashes for artifacts into manifest"
bash "${SCRIPT_DIR}/collect_file_hashes.sh"

log_info "Signing manifest ${DIST_DIR}/manifest.json"
minisign -Sm "${DIST_DIR}/manifest.json" -s "${secret_key_file}" -x "${DIST_DIR}/manifest.json.minisig"

log_info "Verifying manifest signature"
minisign -Vm "${DIST_DIR}/manifest.json" -p "${ROOT_DIR}/keys/cats.pub"

log_info "Verifying artifact signature"
minisign -Vm "${artifact_path}" -p "${ROOT_DIR}/keys/cats.pub"

for comp_name in "${component_names[@]}"; do
  comp_path="${DIST_DIR}/components/${comp_name}"
  comp_sig="${comp_path}.minisig"
  if [[ -f "${comp_path}" && -f "${comp_sig}" ]]; then
    log_info "Verifying component signature for ${comp_name}"
    minisign -Vm "${comp_path}" -p "${ROOT_DIR}/keys/cats.pub"
  fi
done

if command -v shred >/dev/null 2>&1; then
  log_info "Shredding temporary secret key"
  shred -u "${secret_key_file}"
else
  log_info "Removing temporary secret key"
  rm -f "${secret_key_file}"
fi

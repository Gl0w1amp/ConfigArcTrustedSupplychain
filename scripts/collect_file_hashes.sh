#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

MANIFEST_PATH="${DIST_DIR}/manifest.json"
if [[ ! -f "${MANIFEST_PATH}" ]]; then
  log_error "Missing ${MANIFEST_PATH}. Run manifest generation first."
  exit 1
fi

HASH_FILE_REGEX="${HASH_FILE_REGEX:-}"
DEFAULT_REGEX='(?i)\.(exe|dll)$'
USE_REGEX="${HASH_FILE_REGEX:-$DEFAULT_REGEX}"
MAX_HASH_FILES="${MAX_HASH_FILES:-0}"

if [[ "${DISABLE_FILE_HASHES:-0}" == "1" ]]; then
  log_info "DISABLE_FILE_HASHES=1; setting files=[] for all artifacts."
  tmp_out="$(mktemp)"
  jq '.artifacts |= map(. + {files: []})' "${MANIFEST_PATH}" > "${tmp_out}"
  mv "${tmp_out}" "${MANIFEST_PATH}"
  exit 0
fi

tmp_out="$(mktemp)"
artifacts_len="$(jq '.artifacts | length' "${MANIFEST_PATH}")"
log_info "Collecting file hashes for ${artifacts_len} artifact(s)"

collect_for_artifact() {
  local name="$1"
  local kind="$2"
  local files_field

  # Resolve local path
  local local_path="${DIST_DIR}/${name}"
  if [[ ! -f "${local_path}" && "${kind}" == "component" ]]; then
    local_path="${DIST_DIR}/components/${name}"
  fi
  if [[ ! -f "${local_path}" ]]; then
    log_error "Artifact file not found for ${name} (searched dist/ and dist/components/)"
    exit 1
  fi

  log_info "Listing entries in ${local_path}"
  entries="$(unzip -Z1 "${local_path}")"
  matches=()
  while IFS= read -r entry; do
    [[ -z "${entry}" ]] && continue
    [[ "${entry}" == */ ]] && continue
    if [[ "${entry}" =~ ${USE_REGEX} ]]; then
      matches+=("${entry}")
    fi
  done <<< "${entries}"

  if [[ "${MAX_HASH_FILES}" =~ ^[0-9]+$ && "${MAX_HASH_FILES}" -gt 0 && "${#matches[@]}" -gt "${MAX_HASH_FILES}" ]]; then
    matches=("${matches[@]:0:${MAX_HASH_FILES}}")
    log_warn "MAX_HASH_FILES=${MAX_HASH_FILES} reached for ${name}; truncating list."
  fi

  if [[ "${#matches[@]}" -eq 0 ]]; then
    echo "[]" && return 0
  fi

  files_json=()
  for entry in "${matches[@]}"; do
    size_bytes="$(unzip -p "${local_path}" "${entry}" | wc -c)"
    sha="$(unzip -p "${local_path}" "${entry}" | sha256sum | awk '{print $1}')"
    files_json+=("$(jq -n --arg path "${entry}" --arg size "${size_bytes}" --arg sha "${sha}" '{path:$path,size:($size|tonumber),sha256:$sha}')")
  done

  printf '%s\n' "${files_json[@]}" | jq -s '.'
}

jq --argjson artifacts "$(jq '.artifacts' "${MANIFEST_PATH}")" -n '
  {artifacts: $artifacts}
' > "${tmp_out}"

update_tmp="$(mktemp)"

idx=0
while [[ "${idx}" -lt "${artifacts_len}" ]]; do
  name="$(jq -r ".artifacts[${idx}].name" "${MANIFEST_PATH}")"
  kind="$(jq -r ".artifacts[${idx}].kind // \"\"" "${MANIFEST_PATH}")"
  files_json="$(collect_for_artifact "${name}" "${kind}")"
  jq --argjson files "${files_json}" ".artifacts[${idx}] |= (. + {files: \$files})" "${tmp_out}" > "${update_tmp}"
  mv "${update_tmp}" "${tmp_out}"
  idx=$((idx + 1))
done

mv "${tmp_out}" "${MANIFEST_PATH}"
log_info "Updated ${MANIFEST_PATH} with file hashes"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

if [[ "${SPLIT_INNER_ZIPS:-1}" != "1" ]]; then
  log_info "SPLIT_INNER_ZIPS != 1; skipping inner zip extraction."
  exit 0
fi

META_FILE="${DIST_DIR}/upstream_meta.json"
if [[ ! -f "${META_FILE}" ]]; then
  log_error "Missing ${META_FILE}. Run scripts/fetch_upstream.sh first."
  exit 1
fi

outer_name="$(jq -r '.asset_name' "${META_FILE}")"
outer_path="${DIST_DIR}/${outer_name}"
if [[ ! -f "${outer_path}" ]]; then
  log_error "Outer artifact ${outer_path} not found. Run scripts/fetch_upstream.sh first."
  exit 1
fi

INNER_ZIP_REGEX="${INNER_ZIP_REGEX:-(^|.*/)[^/]+\\.zip$}"
MAX_INNER_ZIPS="${MAX_INNER_ZIPS:-0}"

components_dir="${DIST_DIR}/components"
mkdir -p "${components_dir}"

entries_file="${TMP_DIR}/entries.txt"
log_info "Listing entries in ${outer_path}"
unzip -Z1 "${outer_path}" > "${entries_file}"

declare -A used_names=()
json_lines=()
count=0

while IFS= read -r entry; do
  [[ -z "${entry}" ]] && continue
  if [[ ! "${entry}" =~ ${INNER_ZIP_REGEX} ]]; then
    continue
  fi
  # Ensure we are not treating the outer zip itself as a component
  base_entry="$(basename "${entry}")"
  if [[ "${base_entry}" == "${outer_name}" ]]; then
    continue
  fi

  safe_name="${base_entry}"
  if [[ -n "${used_names[${safe_name}]:-}" ]]; then
    safe_name="${entry//\//__}"
  fi
  if [[ -n "${used_names[${safe_name}]:-}" ]]; then
    hash_prefix="$(printf '%s' "${entry}" | sha256sum | cut -c1-8)"
    safe_name="${hash_prefix}_${safe_name}"
  fi
  used_names["${safe_name}"]=1

  dest_path="${components_dir}/${safe_name}"
  log_info "Extracting ${entry} -> ${dest_path}"
  unzip -p "${outer_path}" "${entry}" > "${dest_path}"

  json_lines+=("$(jq -n --arg entry "${entry}" --arg file "dist/components/${safe_name}" --arg name "${safe_name}" '{entry:$entry,file:$file,name:$name}')")

  count=$((count + 1))
  if [[ "${MAX_INNER_ZIPS}" =~ ^[0-9]+$ && "${MAX_INNER_ZIPS}" -gt 0 && "${count}" -ge "${MAX_INNER_ZIPS}" ]]; then
    log_warn "MAX_INNER_ZIPS reached (${MAX_INNER_ZIPS}); stopping extraction."
    break
  fi
done < "${entries_file}"

if [[ "${#json_lines[@]}" -eq 0 ]]; then
  log_info "No inner zips matched; writing empty index."
  jq -n '[]' > "${components_dir}/index.json"
  exit 0
fi

printf '%s\n' "${json_lines[@]}" | jq -s '.' > "${components_dir}/index.json"
log_info "Wrote component index to ${components_dir}/index.json"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

ensure_dist

META_FILE="${DIST_DIR}/upstream_meta.json"
if [[ ! -f "${META_FILE}" ]]; then
  log_error "Missing ${META_FILE}. Run scripts/fetch_upstream.sh first."
  exit 1
fi

artifact_name="$(jq -r '.asset_name' "${META_FILE}")"
artifact_path="${DIST_DIR}/${artifact_name}"
if [[ ! -f "${artifact_path}" ]]; then
  log_error "Artifact ${artifact_path} not found. Run scripts/fetch_upstream.sh."
  exit 1
fi

release_tag="$(jq -r '.release_tag' "${META_FILE}")"
release_name="$(jq -r '.release_name' "${META_FILE}")"
published_at="$(jq -r '.published_at' "${META_FILE}")"
asset_url="$(jq -r '.asset_url' "${META_FILE}")"
release_latest_url="$(jq -r '.release_latest_url' "${META_FILE}")"
build_id="$(jq -r '.build_id' "${META_FILE}")"

r2_prefix="${R2_PREFIX:-configarc/trusted}"
r2_prefix="${r2_prefix%/}"

artifact_size="$(stat -c %s "${artifact_path}" 2>/dev/null || stat -f%z "${artifact_path}")"
artifact_sha="$(sha256sum "${artifact_path}" | awk '{print $1}')"

artifact_sig_path="${artifact_path}.minisig"
artifact_sig_sha=""
if [[ -f "${artifact_sig_path}" ]]; then
  artifact_sig_sha="$(sha256sum "${artifact_sig_path}" | awk '{print $1}')"
else
  if [[ "${EXPECT_SIGNATURES:-0}" == "1" ]]; then
    log_error "Artifact signature ${artifact_sig_path} is required but missing."
    exit 1
  else
    log_warn "Artifact signature ${artifact_sig_path} not found; minisig sha256 will be omitted."
  fi
fi

build_path="builds/${build_id}"

artifact_key="${r2_prefix}/${build_path}/${artifact_name}"
artifact_sig_key="${r2_prefix}/${build_path}/${artifact_name}.minisig"
manifest_key="${r2_prefix}/${build_path}/manifest.json"
manifest_sig_key="${r2_prefix}/${build_path}/manifest.json.minisig"
latest_manifest_key="${r2_prefix}/latest/manifest.json"
latest_manifest_sig_key="${r2_prefix}/latest/manifest.json.minisig"

log_info "Generating manifest at ${DIST_DIR}/manifest.json"
generated_at="$(iso_utc_now)"

outer_entry="$(jq -n \
  --arg name "${artifact_name}" \
  --arg artifact_key "${artifact_key}" \
  --arg artifact_size "${artifact_size}" \
  --arg artifact_sha "${artifact_sha}" \
  --arg artifact_sig_name "${artifact_name}.minisig" \
  --arg artifact_sig_key "${artifact_sig_key}" \
  --arg artifact_sig_sha "${artifact_sig_sha}" \
  '{
    kind: "bundle",
    name: $name,
    r2_key: $artifact_key,
    size: ($artifact_size | tonumber),
    sha256: $artifact_sha,
    minisig: {
      name: $artifact_sig_name,
      r2_key: $artifact_sig_key,
      sha256: (if $artifact_sig_sha == "" then null else $artifact_sig_sha end)
    }
  }')"

entries_tmp="$(mktemp)"
printf '%s\n' "${outer_entry}" > "${entries_tmp}"

components_index="${DIST_DIR}/components/index.json"
include_components=0
if [[ "${SPLIT_INNER_ZIPS:-1}" == "1" && -f "${components_index}" ]]; then
  include_components=1
fi

if [[ "${include_components}" -eq 1 ]]; then
  log_info "Including components from ${components_index}"
  while IFS= read -r line; do
    entry_path="$(jq -r '.entry' <<< "${line}")"
    comp_name="$(jq -r '.name' <<< "${line}")"
    comp_file="${DIST_DIR}/components/${comp_name}"
    if [[ ! -f "${comp_file}" ]]; then
      log_warn "Component file ${comp_file} listed in index but not found; skipping."
      continue
    fi
    comp_size="$(stat -c %s "${comp_file}" 2>/dev/null || stat -f%z "${comp_file}")"
    comp_sha="$(sha256sum "${comp_file}" | awk '{print $1}')"
    comp_sig_path="${comp_file}.minisig"
    comp_sig_sha=""
    if [[ -f "${comp_sig_path}" ]]; then
      comp_sig_sha="$(sha256sum "${comp_sig_path}" | awk '{print $1}')"
    else
      if [[ "${EXPECT_SIGNATURES:-0}" == "1" ]]; then
        log_error "Component signature ${comp_sig_path} is required but missing."
        exit 1
      else
        log_warn "Component signature ${comp_sig_path} not found; minisig sha256 will be omitted."
      fi
    fi
    comp_key="${r2_prefix}/${build_path}/components/${comp_name}"
    comp_sig_key="${comp_key}.minisig"

    comp_entry="$(jq -n \
      --arg name "${comp_name}" \
      --arg entry "${entry_path}" \
      --arg comp_key "${comp_key}" \
      --arg comp_sig_key "${comp_sig_key}" \
      --arg comp_sig_name "${comp_name}.minisig" \
      --arg comp_size "${comp_size}" \
      --arg comp_sha "${comp_sha}" \
      --arg comp_sig_sha "${comp_sig_sha}" \
      --arg bundle_name "${artifact_name}" \
      --arg bundle_sha "${artifact_sha}" \
      '{
        kind: "component",
        name: $name,
        r2_key: $comp_key,
        size: ($comp_size | tonumber),
        sha256: $comp_sha,
        minisig: {
          name: $comp_sig_name,
          r2_key: $comp_sig_key,
          sha256: (if $comp_sig_sha == "" then null else $comp_sig_sha end)
        },
        origin: {
          bundle_name: $bundle_name,
          bundle_sha256: $bundle_sha,
          entry: $entry
        }
      }')"
    printf '%s\n' "${comp_entry}" >> "${entries_tmp}"
  done < <(jq -cr '.[]' "${components_index}")
fi

artifacts_json="$(jq -s '.' "${entries_tmp}")"

jq -n \
  --arg generated_at "${generated_at}" \
  --arg build_id "${build_id}" \
  --arg release_latest_url "${release_latest_url}" \
  --arg release_tag "${release_tag}" \
  --arg release_name "${release_name}" \
  --arg published_at "${published_at}" \
  --arg asset_name "${artifact_name}" \
  --arg asset_url "${asset_url}" \
  --arg public_key_path "keys/cats.pub" \
  --arg r2_prefix "${r2_prefix}" \
  --arg build_path "${build_path}" \
  --arg manifest_key "${manifest_key}" \
  --arg manifest_sig_key "${manifest_sig_key}" \
  --arg latest_manifest_key "${latest_manifest_key}" \
  --arg latest_manifest_sig_key "${latest_manifest_sig_key}" \
  --argjson artifacts "${artifacts_json}" \
  '{
    schema_version: 1,
    generated_at: $generated_at,
    build_id: $build_id,
    upstream: {
      release_latest_url: $release_latest_url,
      release_tag: $release_tag,
      release_name: $release_name,
      published_at: $published_at,
      asset_name: $asset_name,
      asset_url: $asset_url,
      source: "gitea_release_latest_api"
    },
    artifacts: $artifacts,
    public_key: {
      format: "minisign",
      path_in_repo: $public_key_path
    },
    r2: {
      prefix: $r2_prefix,
      build_path: $build_path,
      manifest: {
        r2_key: $manifest_key
      },
      manifest_sig: {
        r2_key: $manifest_sig_key
      },
      latest: {
        manifest: {
          r2_key: $latest_manifest_key
        },
        manifest_sig: {
          r2_key: $latest_manifest_sig_key
        }
      }
    }
  }
  | (.artifacts |= map(if .minisig.sha256 == null then .minisig |= with_entries(select(.key != "sha256")) else . end))' \
  > "${DIST_DIR}/manifest.json"

log_info "Manifest written to ${DIST_DIR}/manifest.json"

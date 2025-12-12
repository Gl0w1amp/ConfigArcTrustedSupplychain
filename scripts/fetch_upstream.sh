#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

UPSTREAM_RELEASE_LATEST_URL="${UPSTREAM_RELEASE_LATEST_URL:-https://gitea.tendokyu.moe/api/v1/repos/TeamTofuShop/segatools/releases/latest}"
UPSTREAM_ASSET_REGEX="${UPSTREAM_ASSET_REGEX:-^segatools\\.zip$}"

ensure_dist

log_info "Fetching latest release metadata from ${UPSTREAM_RELEASE_LATEST_URL}"
release_json="${TMP_DIR}/release.json"

curl_opts=(-fsSL "${UPSTREAM_RELEASE_LATEST_URL}")
if [[ -n "${UPSTREAM_TOKEN:-}" ]]; then
  curl_opts=(-fsSL -H "Authorization: token ${UPSTREAM_TOKEN}" "${UPSTREAM_RELEASE_LATEST_URL}")
fi

curl "${curl_opts[@]}" -o "${release_json}"

asset_name="$(jq -r --arg regex "${UPSTREAM_ASSET_REGEX}" '[.assets[] | select(.name|test($regex))][0].name // empty' "${release_json}")"
asset_url="$(jq -r --arg regex "${UPSTREAM_ASSET_REGEX}" '[.assets[] | select(.name|test($regex))][0].browser_download_url // empty' "${release_json}")"
release_tag="$(jq -r '.tag_name // empty' "${release_json}")"
release_name="$(jq -r '.name // empty' "${release_json}")"
published_at="$(jq -r '.published_at // empty' "${release_json}")"

if [[ -z "${asset_name}" || -z "${asset_url}" ]]; then
  log_error "No asset matching regex ${UPSTREAM_ASSET_REGEX} was found in the latest release."
  exit 1
fi

build_id="${release_tag:-$(date -u +"%Y%m%d-%H%M%SZ")}"

log_info "Selected asset ${asset_name} (build_id=${build_id})"
artifact_dest="${DIST_DIR}/${asset_name}"

download_opts=(-fL "${asset_url}" -o "${artifact_dest}")
if [[ -n "${UPSTREAM_TOKEN:-}" ]]; then
  download_opts=(-fL -H "Authorization: token ${UPSTREAM_TOKEN}" "${asset_url}" -o "${artifact_dest}")
fi

log_info "Downloading asset to ${artifact_dest}"
curl "${download_opts[@]}"

jq -n \
  --arg release_tag "${release_tag}" \
  --arg release_name "${release_name}" \
  --arg published_at "${published_at}" \
  --arg asset_name "${asset_name}" \
  --arg asset_url "${asset_url}" \
  --arg release_latest_url "${UPSTREAM_RELEASE_LATEST_URL}" \
  --arg build_id "${build_id}" \
  '{
    release_tag: $release_tag,
    release_name: $release_name,
    published_at: $published_at,
    asset_name: $asset_name,
    asset_url: $asset_url,
    release_latest_url: $release_latest_url,
    build_id: $build_id,
    source: "gitea_release_latest_api"
  }' > "${DIST_DIR}/upstream_meta.json"

log_info "Saved upstream metadata to ${DIST_DIR}/upstream_meta.json"

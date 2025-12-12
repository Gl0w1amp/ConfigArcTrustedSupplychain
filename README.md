# ConfigArc Trusted Supplychain

ConfigArc Trusted Supplychain is an automated pipeline that fetches the latest upstream builds, signs them, and publishes trusted artifacts to R2 for ConfigArc Launcher to download and verify.

## What it does
- Fetch the latest upstream release asset from Gitea as the outer bundle.
- Optionally extract inner zip components from the bundle (default on) while still keeping the bundle as the source of truth.
- Generate upstream metadata and a signed manifest describing the build.
- Sign the bundle, each component, and the manifest with Minisign (Ed25519) using a private key provided via secrets.
- Upload the bundle/components, signatures, and manifest to Cloudflare R2, updating both a versioned path and `latest/manifest.json`.

## Repository layout
- `scripts/`: fetch, component extraction, manifest generation, signing, and R2 upload helpers.
- `dist/`: build outputs (bundle, components, minisigs, manifest) created at runtime.
- `keys/cats.pub`: committed Minisign public key.
- `.github/workflows/publish.yml`: GitHub Actions pipeline.

## Required GitHub secrets/variables
- Secrets:
  - `R2_ACCOUNT_ID`
  - `R2_ACCESS_KEY_ID`
  - `R2_SECRET_ACCESS_KEY`
  - `R2_BUCKET`
  - `MINISIGN_SECRET_KEY_B64` (base64 of `minisign.key`)
  - `UPSTREAM_TOKEN` (optional; only if upstream requires it)
- Variables (optional):
  - `R2_PREFIX` (default: `configarc/trusted`)
  - `R2_PUBLIC_BASE_URL` (print public URL if provided)
  - `UPSTREAM_RELEASE_LATEST_URL`, `UPSTREAM_ASSET_REGEX` (override defaults)
  - `SPLIT_INNER_ZIPS` (default `1`; set `0` to skip component extraction)
  - `INNER_ZIP_REGEX` (default `(^|.*/)[^/]+\.zip$`; filters inner zip entries)
  - `MAX_INNER_ZIPS` (optional limit; `0` or unset = no limit)
  - `DISABLE_FILE_HASHES` (set `1` to skip file-level hashes; default on)
  - `HASH_FILE_REGEX` (regex for files inside zips; default matches `*.exe`/`*.dll`, case-insensitive)
  - `MAX_HASH_FILES` (per-artifact hash cap; `0` or unset = no limit)

## Cloudflare R2 object layout
```
s3://$R2_BUCKET/$R2_PREFIX/
  latest/manifest.json
  latest/manifest.json.minisig
  builds/<build_id>/
    <bundle>.zip
    <bundle>.zip.minisig
    components/
      <component>.zip
      <component>.zip.minisig
    # manifest also records inner file hashes for executables by default
    manifest.json
    manifest.json.minisig
```

## Local run (manual)
```bash
export MINISIGN_SECRET_KEY_B64=... \
       R2_ACCOUNT_ID=... \
       R2_ACCESS_KEY_ID=... \
       R2_SECRET_ACCESS_KEY=... \
       R2_BUCKET=... \
       R2_PREFIX="configarc/trusted"

scripts/fetch_upstream.sh
scripts/extract_inner_zips.sh
scripts/generate_manifest.sh
scripts/sign_all.sh
scripts/upload_r2.sh
```

## Verification
After CI runs, download the manifest and artifacts and verify with the committed public key:
```bash
minisign -Vm dist/manifest.json -p keys/cats.pub
minisign -Vm dist/<artifact> -p keys/cats.pub
```

## ConfigArc Launcher consumption
- Download `latest/manifest.json` and `latest/manifest.json.minisig`.
- Verify the manifest using `keys/cats.pub` (embedded in the Launcher).
- Prefer downloading individual components (entries with `kind: "component"`) and verify them with the minisig/public key.
- If components are unavailable or disabled, fall back to the bundle (entry with `kind: "bundle"`), download and verify its minisig, then proceed.
 - After verifying the manifest, validate the unpacked install directory: for each artifact, check the `files` array (path/size/sha256) for listed executables to ensure on-disk contents match.

## CI workflow
- Triggered on `push` to `main`, daily cron, or manual dispatch.
- Steps: install deps → fetch upstream → extract inner zips → generate manifest → collect file hashes → sign bundle+components+manifest → upload to R2 → print latest manifest URL.
- Uses Minisign from apt or falls back to a static binary download if needed.

## License
SPDX-License-Identifier: AGPL-3.0-only

This project is licensed under the GNU Affero General Public License v3.0. See `LICENSE` for details.

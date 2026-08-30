#!/usr/bin/env bash
#
# Builds a Release copy of Notchboard, zips it the way macOS expects, and prints the
# sha256 the cask needs. Everything that requires an Apple account (Developer ID signing,
# notarisation, stapling) is printed as commands to run by hand, never executed here, so
# this script works on a machine with no certificates and no App Store Connect key.
#
# See website/content/docs/documentation/releasing.mdx for the full checklist and for why an unsigned download is
# refused by Gatekeeper.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT="${REPO_ROOT}/notchboard.xcodeproj"
readonly SCHEME="notchboard"

# Defaults, all overridable. Both live under the repo and are gitignored (build/).
DERIVED_DATA="${REPO_ROOT}/build/DerivedData"
OUTPUT_DIR="${REPO_ROOT}/build/release"
VERSION=""

usage() {
  cat <<'EOS'
release.sh: build Notchboard for release and print the cask checksum.

Usage:
  scripts/release.sh [options]

Options:
  --version <x.y.z>    Version used in the artefact name and the printed cask lines.
                       Defaults to MARKETING_VERSION read from the project.
  --output <dir>       Where the .app and the .zip are written.
                       Default: build/release
  --derived-data <dir> Build directory passed to xcodebuild.
                       Default: build/DerivedData
  --clean              Delete the derived data directory before building.
  -h, --help           Show this help.

What it does:
  1. Builds the Release configuration for macOS (arm64 + x86_64).
  2. Copies the built .app into the output directory.
  3. Zips it with `ditto -c -k --keepParent`, which is the only archiver that keeps
     symlinks and resource forks intact inside a bundle.
  4. Prints the sha256 and the two cask lines to update.
  5. Prints the signing and notarisation commands for you to run yourself.

What it deliberately does not do:
  Nothing here runs codesign, notarytool or stapler. Those need your Developer ID
  certificate and an App Store Connect credential, so they stay in your hands.

Safe to re-run: the output directory is rebuilt from scratch on every run.
EOS
}

log() { printf '\033[1m==>\033[0m %s\n' "$*"; }

die() {
  printf 'release.sh: %s\n' "$*" >&2
  exit 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || die "--version needs a value"
        VERSION="$2"
        shift 2
        ;;
      --output)
        [[ $# -ge 2 ]] || die "--output needs a value"
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --derived-data)
        [[ $# -ge 2 ]] || die "--derived-data needs a value"
        DERIVED_DATA="$2"
        shift 2
        ;;
      --clean)
        CLEAN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1 (try --help)"
        ;;
    esac
  done
}

# Reads one build setting out of the project. Used for the version and for locating the
# product, so the script never hardcodes "notchboard.app" or a Products path.
build_setting() {
  local key="$1"
  xcodebuild -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "${DERIVED_DATA}" \
    -showBuildSettings 2>/dev/null \
    | sed -n "s/^[[:space:]]*${key} = //p" \
    | head -n 1
}

main() {
  CLEAN=0
  parse_args "$@"

  command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found. Install Xcode."
  [[ -d "${PROJECT}" ]] || die "project not found at ${PROJECT}"

  if [[ "${CLEAN}" -eq 1 ]]; then
    log "removing ${DERIVED_DATA}"
    rm -rf "${DERIVED_DATA}"
  fi

  log "reading build settings"
  local product_name built_products_dir
  product_name="$(build_setting FULL_PRODUCT_NAME)"
  built_products_dir="$(build_setting BUILT_PRODUCTS_DIR)"
  [[ -n "${product_name}" ]] || die "could not read FULL_PRODUCT_NAME from the project"
  [[ -n "${built_products_dir}" ]] || die "could not read BUILT_PRODUCTS_DIR from the project"

  if [[ -z "${VERSION}" ]]; then
    VERSION="$(build_setting MARKETING_VERSION)"
    [[ -n "${VERSION}" ]] || die "could not read MARKETING_VERSION. Pass --version instead."
  fi

  log "building ${product_name} ${VERSION} (Release, arm64 + x86_64)"
  xcodebuild -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "${DERIVED_DATA}" \
    build

  local built_app="${built_products_dir}/${product_name}"
  [[ -d "${built_app}" ]] || die "build finished but ${built_app} is missing"

  # Rebuilt every run so a failed or older attempt can never leak into the artefact.
  rm -rf "${OUTPUT_DIR}"
  mkdir -p "${OUTPUT_DIR}"

  local staged_app="${OUTPUT_DIR}/${product_name}"
  local zip_name="notchboard-${VERSION}.zip"
  local zip_path="${OUTPUT_DIR}/${zip_name}"

  log "staging ${staged_app}"
  # ditto rather than cp: it preserves the bundle's symlinks and extended attributes,
  # which a later codesign run depends on.
  ditto "${built_app}" "${staged_app}"

  log "zipping ${zip_name}"
  ditto -c -k --keepParent "${staged_app}" "${zip_path}"

  local checksum size
  checksum="$(shasum -a 256 "${zip_path}" | awk '{ print $1 }')"
  size="$(du -h "${zip_path}" | awk '{ print $1 }')"

  cat <<EOS

------------------------------------------------------------------------------
Built:     ${staged_app}
Archive:   ${zip_path}  (${size})
sha256:    ${checksum}

The .app is ad-hoc signed, because DEVELOPMENT_TEAM is empty and CODE_SIGN_IDENTITY
is "-" in every configuration. That is fine for running it locally and useless for a
download: macOS quarantines anything fetched over the network and refuses to open it,
with a dialog that says the app is damaged or that Apple could not verify it. Sign and
notarise before uploading anything anyone else will install.

STEP 1: sign with Developer ID (replace the identity)
  Find yours with: security find-identity -v -p codesigning

  Sign inside-out: nested binaries first, the bundle last. The Swift compatibility
  dylibs in Contents/Frameworks keep their ad-hoc signature otherwise, and the notary
  service rejects the whole archive over them. (--deep also covers them but Apple has
  deprecated it.)

  for dylib in "${staged_app}"/Contents/Frameworks/*.dylib; do
    codesign --force --options runtime --timestamp \\
      --sign "Developer ID Application: YOUR NAME (TEAMID)" "\$dylib"
  done
  codesign --force --options runtime --timestamp \\
    --sign "Developer ID Application: YOUR NAME (TEAMID)" \\
    "${staged_app}"
  codesign --verify --deep --strict "${staged_app}"

  Then re-zip, because the signature has to be inside the archive:
  rm -f "${zip_path}"
  ditto -c -k --keepParent "${staged_app}" "${zip_path}"

STEP 2: notarise (replace the profile name)
  Store the credential once, interactively:
  xcrun notarytool store-credentials "YOUR-PROFILE-NAME" \\
    --apple-id "you@example.com" --team-id "TEAMID"

  xcrun notarytool submit "${zip_path}" \\
    --keychain-profile "YOUR-PROFILE-NAME" --wait

STEP 3: staple the ticket to the app, then re-zip one last time
  xcrun stapler staple "${staged_app}"
  rm -f "${zip_path}"
  ditto -c -k --keepParent "${staged_app}" "${zip_path}"
  spctl --assess --type execute --verbose "${staged_app}"

STEP 4: recompute the checksum, because every re-zip changes it
  shasum -a 256 "${zip_path}"

STEP 5: publish and update the cask
  gh release create "v${VERSION}" "${zip_path}" --title "v${VERSION}" --notes "..."

  In Casks/notchboard.rb, and in the copy in the tap repository:
    version "${VERSION}"
    sha256 "<the checksum from step 4>"
------------------------------------------------------------------------------
EOS
}

main "$@"

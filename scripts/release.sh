#!/usr/bin/env bash
#
# Builds a Release copy of Notchboard, zips it the way macOS expects, and prints the
# sha256 the cask needs. Everything that requires an Apple account (Developer ID signing,
# notarisation, stapling) or the Sparkle signing key (the appcast) is printed as commands
# to run by hand, never executed here, so this script works on a machine with no
# certificates, no App Store Connect key and no EdDSA key.
#
# The one value it stamps is CFBundleVersion. Sparkle compares that number, not the
# marketing version, to decide whether a release is newer, and project.pbxproj freezes
# CURRENT_PROJECT_VERSION at 1 so a local build never looks newer than a release. The
# build number is derived from MARKETING_VERSION (1.2 becomes 10200) and passed on the
# xcodebuild line only, so it lives nowhere in the tracked project (vision.md §13.20).
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
BUILD_NUMBER=""

usage() {
  cat <<'EOS'
release.sh: build Notchboard for release and print the cask checksum.

Usage:
  scripts/release.sh [options]

Options:
  --version <x.y>      Version used in the artefact name and the printed cask lines.
                       Must equal MARKETING_VERSION in the project, and defaults to it.
                       Two numeric components only: Homebrew's version comparison bails
                       when the dot-component counts differ, so a hotfix bumps MINOR
                       rather than adding a third part.
  --build-number <n>   CFBundleVersion for this build, digits only. Sparkle compares
                       this number to decide whether an update is newer.
                       Default: MAJOR*10000 + MINOR*100 (1.2 becomes 10200).
  --output <dir>       Where the .app and the .zip are written.
                       Default: build/release
  --derived-data <dir> Build directory passed to xcodebuild.
                       Default: build/DerivedData
  --clean              Delete the derived data directory before building.
  -h, --help           Show this help.

What it does:
  1. Builds the Release configuration for macOS (arm64 + x86_64), stamping the build
     number into CFBundleVersion on the xcodebuild line.
  2. Copies the built .app into the output directory and checks that its Info.plist
     carries that build number, SUFeedURL and SUPublicEDKey, and that Sparkle.framework
     is embedded.
  3. Zips it with `ditto -c -k --keepParent`, which is the only archiver that keeps
     symlinks and resource forks intact inside a bundle.
  4. Prints the sha256 and the two cask lines to update.
  5. Prints the signing, notarisation and appcast commands for you to run yourself.

What it deliberately does not do:
  Nothing here runs codesign, notarytool, stapler or generate_appcast. Those need your
  Developer ID certificate, an App Store Connect credential and the Sparkle signing
  key, so they stay in your hands.

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
      --build-number)
        [[ $# -ge 2 ]] || die "--build-number needs a value"
        [[ "$2" =~ ^[0-9]+$ ]] || die "--build-number must be digits only, got '$2'"
        BUILD_NUMBER="$2"
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

# Sparkle decides "newer" by comparing CFBundleVersion, so the number has to grow with
# every release. MAJOR*10000 + MINOR*100 (1.2 becomes 10200) does that for two-component
# versions and leaves room below the next minor for a rehearsal build (vision.md §13.20).
derive_build_number() {
  local version="$1"
  local major="${version%%.*}"
  local minor="${version#*.}"
  printf '%d' "$(( 10#${major} * 10000 + 10#${minor} * 100 ))"
}

# Reads one key out of an Info.plist as a bare value. Prints nothing when the key is
# absent, so callers test for emptiness instead of parsing plutil's error.
plist_value() {
  plutil -extract "$1" raw -o - "$2" 2>/dev/null || true
}

# Everything an installed copy needs to update itself later is checked here, before the
# zip exists, because a missing key or framework would otherwise surface only on a
# user's Mac as an update that never arrives (vision.md §13.20).
assert_staged_bundle() {
  local app="$1"
  local plist="${app}/Contents/Info.plist"
  local value
  value="$(plist_value CFBundleVersion "${plist}")"
  [[ "${value}" == "${BUILD_NUMBER}" ]] \
    || die "CFBundleVersion is '${value}', expected ${BUILD_NUMBER}. Did the CURRENT_PROJECT_VERSION override reach xcodebuild?"
  value="$(plist_value SUFeedURL "${plist}")"
  [[ -n "${value}" ]] || die "SUFeedURL is missing from ${plist}"
  value="$(plist_value SUPublicEDKey "${plist}")"
  [[ -n "${value}" ]] || die "SUPublicEDKey is missing from ${plist}"
  [[ -d "${app}/Contents/Frameworks/Sparkle.framework" ]] \
    || die "Contents/Frameworks/Sparkle.framework is missing from ${app}. The build did not embed the Sparkle package."
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

  # The project is the single source of the version. A --version that disagrees is
  # refused rather than trusted: the tag, the zip name, the cask pin and what the app
  # reports about itself must all say the same thing, and only the project can make that
  # true (vision.md §13.20).
  local project_version
  project_version="$(build_setting MARKETING_VERSION)"
  [[ -n "${project_version}" ]] || die "could not read MARKETING_VERSION from the project"
  if [[ -n "${VERSION}" && "${VERSION}" != "${project_version}" ]]; then
    die "--version ${VERSION} does not match MARKETING_VERSION ${project_version}. Bump the project (and the changelog), then tag."
  fi
  VERSION="${project_version}"
  [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+$ ]] \
    || die "MARKETING_VERSION must be two numeric components (MAJOR.MINOR), got '${VERSION}'"
  if [[ -z "${BUILD_NUMBER}" ]]; then
    BUILD_NUMBER="$(derive_build_number "${VERSION}")"
  fi

  log "building ${product_name} ${VERSION} build ${BUILD_NUMBER} (Release, arm64 + x86_64)"
  # CURRENT_PROJECT_VERSION stays 1 in project.pbxproj so a local build never looks newer
  # than a release. The real number exists only on this command line.
  xcodebuild -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "${DERIVED_DATA}" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
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

  log "checking the staged bundle"
  assert_staged_bundle "${staged_app}"

  log "zipping ${zip_name}"
  ditto -c -k --keepParent "${staged_app}" "${zip_path}"

  local checksum size
  checksum="$(shasum -a 256 "${zip_path}" | awk '{ print $1 }')"
  size="$(du -h "${zip_path}" | awk '{ print $1 }')"
  local appcast_dir="${REPO_ROOT}/build/appcast"

  cat <<EOS

------------------------------------------------------------------------------
Built:     ${staged_app}
Version:   ${VERSION}  (CFBundleVersion ${BUILD_NUMBER})
Archive:   ${zip_path}  (${size})
sha256:    ${checksum}

The .app is ad-hoc signed, because DEVELOPMENT_TEAM is empty and CODE_SIGN_IDENTITY
is "-" in every configuration. That is fine for running it locally and useless for a
download: macOS quarantines anything fetched over the network and refuses to open it,
with a dialog that says the app is damaged or that Apple could not verify it. Sign and
notarise before uploading anything anyone else will install.

STEP 1: sign with Developer ID (replace the identity)
  Find yours with: security find-identity -v -p codesigning

  Sign inside-out: nested code first, the bundle last. Sparkle's XPC services, helper
  and Updater.app ship with Sparkle's own signature and the Swift compatibility dylibs
  keep their ad-hoc one, so the notary service rejects the whole archive unless every
  nested binary carries your identity. (--deep also covers them but Apple has
  deprecated it. The --preserve-metadata=entitlements on Downloader.xpc follows
  Sparkle's own recipe; that service carries no entitlements in 2.9.6, so the flag
  preserves nothing today.)

  sparkle="${staged_app}/Contents/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp \\
    --sign "Developer ID Application: YOUR NAME (TEAMID)" \\
    "\$sparkle/Versions/B/XPCServices/Installer.xpc"
  codesign --force --options runtime --timestamp --preserve-metadata=entitlements \\
    --sign "Developer ID Application: YOUR NAME (TEAMID)" \\
    "\$sparkle/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --options runtime --timestamp \\
    --sign "Developer ID Application: YOUR NAME (TEAMID)" \\
    "\$sparkle/Versions/B/Autoupdate"
  codesign --force --options runtime --timestamp \\
    --sign "Developer ID Application: YOUR NAME (TEAMID)" \\
    "\$sparkle/Versions/B/Updater.app"
  codesign --force --options runtime --timestamp \\
    --sign "Developer ID Application: YOUR NAME (TEAMID)" \\
    "\$sparkle"
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

STEP 4b: generate the appcast (the Sparkle CLI must match the embedded framework)
  Installed copies read the appcast to learn that this release exists. generate_appcast
  signs it with the EdDSA key that generate_keys stored in your login keychain, whose
  public half is SUPublicEDKey in Info.plist. Give it a directory holding only the final
  zip and the release notes named after it, as Markdown:
  mkdir -p "${appcast_dir}"
  cp "${zip_path}" "${appcast_dir}/"
  cp <the changelog section for ${VERSION}> "${appcast_dir}/notchboard-${VERSION}.md"
  generate_appcast \\
    --download-url-prefix "https://github.com/thepearl/notchboard/releases/download/v${VERSION}/" \\
    --embed-release-notes --link "https://github.com/thepearl/notchboard" \\
    --full-release-notes-url "https://thepearl.github.io/notchboard/changelog/" \\
    -o "${appcast_dir}/appcast.xml" "${appcast_dir}"

STEP 5: bump the tap, then publish

  The tap goes first, so its pin never lags the download it describes. Copy this repo's
  Casks/notchboard.rb into the tap's Casks/ and stamp the two placeholder lines on that
  copy only — the in-repo file keeps its placeholders:
    version "${VERSION}"
    sha256 "<the checksum from step 4>"

  gh release create "v${VERSION}" "${zip_path}" "${appcast_dir}/appcast.xml" \\
    "${REPO_ROOT}/THIRD-PARTY-NOTICES.md" --title "v${VERSION}" \\
    --notes-file "${appcast_dir}/notchboard-${VERSION}.md" --latest --verify-tag
------------------------------------------------------------------------------
EOS
}

main "$@"

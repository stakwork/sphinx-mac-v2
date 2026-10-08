#!/bin/sh
# Embed liblbug (swift-ladybug) and its vendored OpenSSL deps into the app
# bundle's Frameworks folder, then sign them — mirrors sign-strut-nested.sh's
# conventions for the other third-party dylibs this target already vendors
# (libonnxruntime.dylib, libsherpa-onnx-c-api.dylib under Strut's native/).
#
# Without this, liblbug only loads via an LC_RPATH entry pointing at the
# local SwiftPM checkout inside DerivedData (added by the "Download liblbug
# (swift-ladybug)" phase, which also vendors+signs the files there — that
# phase runs early, before this app's .app bundle structure exists, purely
# so the LINK step succeeds). That path is real on a developer's own machine
# but does not exist once the app is archived, notarized, or run on any
# other machine, so the app would fail to launch outside of local dev
# builds with "Library not loaded" — this phase is what actually makes the
# dependency part of the shipped app rather than a dev-machine-only crutch.
#
# Invoked from the Sphinx target "Embed liblbug (swift-ladybug)" run-script
# phase, positioned after the Frameworks (link) phase so the bundle
# structure already exists, and before the app's own final code-signing.

set -euo pipefail

# SourcePackages always lives directly under the true DerivedData project
# root, but how many levels BUILD_DIR sits below that root varies by build
# action -- a plain Debug/Release build puts it at <root>/Build/Products,
# while Archive nests it much deeper under
# <root>/Build/Intermediates.noindex/ArchiveIntermediates/<target>/BuildProductsPath.
# Walk upward looking for a SourcePackages sibling instead of assuming a
# fixed number of ../.. hops, so this works for both.
DERIVED_DATA_ROOT=""
SEARCH_DIR="${BUILD_DIR}"
for _ in 1 2 3 4 5 6 7 8; do
  SEARCH_DIR="$(cd "${SEARCH_DIR}/.." && pwd)"
  if [ -d "${SEARCH_DIR}/SourcePackages" ]; then
    DERIVED_DATA_ROOT="${SEARCH_DIR}"
    break
  fi
done
if [ -z "${DERIVED_DATA_ROOT}" ]; then
  echo "warning: could not locate SourcePackages above BUILD_DIR=${BUILD_DIR} -- skipping embed" >&2
  exit 0
fi

LADYBUG_LIB_DIR="${DERIVED_DATA_ROOT}/SourcePackages/checkouts/swift-ladybug/lib"
DEST="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"

# `|| true` neutralizes ls's failure when the glob matches nothing -- under
# pipefail that failure would otherwise propagate through `| head -n1` and
# trip `set -e` right here, before the graceful empty-check below ever runs.
LIBLBUG_SRC="$(ls "${LADYBUG_LIB_DIR}"/liblbug.*.*.dylib 2>/dev/null | head -n1 || true)"
if [ -z "${LIBLBUG_SRC}" ] || [ ! -f "${LIBLBUG_SRC}" ]; then
  echo "warning: no liblbug dylib found under ${LADYBUG_LIB_DIR} -- skipping embed (did the download phase run?)" >&2
  exit 0
fi
if [ ! -f "${LADYBUG_LIB_DIR}/libssl.3.dylib" ] || [ ! -f "${LADYBUG_LIB_DIR}/libcrypto.3.dylib" ]; then
  echo "warning: vendored libssl/libcrypto not found under ${LADYBUG_LIB_DIR} -- skipping embed" >&2
  exit 0
fi

mkdir -p "${DEST}"

# -L dereferences the liblbug.0.dylib symlink so the real Mach-O content
# lands under the exact name @rpath/liblbug.0.dylib resolves to -- the
# load commands already point at this filename, so no install_name_tool
# rewrite is needed here, only for the original vendoring step.
cp -L "${LADYBUG_LIB_DIR}/liblbug.0.dylib" "${DEST}/liblbug.0.dylib"
cp "${LADYBUG_LIB_DIR}/libssl.3.dylib" "${DEST}/libssl.3.dylib"
cp "${LADYBUG_LIB_DIR}/libcrypto.3.dylib" "${DEST}/libcrypto.3.dylib"
chmod u+w "${DEST}/liblbug.0.dylib" "${DEST}/libssl.3.dylib" "${DEST}/libcrypto.3.dylib"

if [ -z "${IDENTITY}" ] || [ "${IDENTITY}" = "-" ]; then
  echo "note: no code-signing identity; embedded liblbug/libssl/libcrypto left unsigned"
  exit 0
fi

TIMESTAMP_FLAG="--timestamp"
if [ "${CONFIGURATION:-}" = "Debug" ]; then
  TIMESTAMP_FLAG="--timestamp=none"
fi

for f in "${DEST}/liblbug.0.dylib" "${DEST}/libssl.3.dylib" "${DEST}/libcrypto.3.dylib"; do
  codesign --force --sign "${IDENTITY}" --options runtime ${TIMESTAMP_FLAG} "$f"
done

echo "Embedded and signed liblbug + libssl + libcrypto in ${DEST} with ${IDENTITY}"

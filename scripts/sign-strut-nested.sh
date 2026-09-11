#!/bin/sh
# Sign nested Strut Mach-O after the Embed Strut Helper copy phase.
# Team ID 8297M44YTW (DEVELOPMENT_TEAM). Hardened runtime, no --deep.
# Helper entitlements: sandbox inherit + cs.allow-jit (StrutNode.entitlements).
# Do NOT pass com.apple.security.cs.disable-library-validation.
# Do NOT pass cs.allow-unsigned-executable-memory unless a signed Apple Silicon
# spike shows V8 isolate setup dying (helper only, never the parent).
#
# The Strut tree lands at `Contents/Strut`, NOT `Contents/Helpers/Strut`.
# `Contents/Helpers/` is a reserved bundle location (like Frameworks/
# PlugIns/XPCServices) — codesign requires EVERYTHING under it to be
# independently-signed nested code and rejects any plain resource file
# there outright, confirmed with a minimal repro (`Contents/Helpers/x/
# resource.txt` alone, no Mach-O involved, fails to seal; the identical
# tree under `Contents/Strut/` signs fine). Do not move this back under
# Helpers/.
#
# All Mach-O the host code-signs also live in one binaries-only directory,
# `native/` (relocated there by strut's own `scripts/package-desktop.mjs`
# for its addon, and by our vendoring for `node`) — not required to satisfy
# the Helpers/ rule above, but kept because strut's own packaging already
# does it and it keeps every signable binary in one place. This script
# exists instead of `codeSignOnCopy` because that also can't be set on the
# folder-reference copy of the whole tree (it is not a bundle).
#
# Invoked from the Sphinx target "Sign Strut Nested Code" run-script phase.

set -euo pipefail

HELPER="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Strut"
ENTITLEMENTS="${SRCROOT}/com.stakwork.sphinx.desktop/StrutNode.entitlements"
NATIVE="${HELPER}/native"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"

if [ ! -d "${HELPER}" ]; then
  echo "error: Strut helper missing at ${HELPER}" >&2
  exit 1
fi
if [ ! -f "${NATIVE}/node" ] || [ ! -f "${NATIVE}/sherpa-onnx.node" ]; then
  echo "error: nested Strut Mach-O missing under ${NATIVE}" >&2
  exit 1
fi

if [ -z "${IDENTITY}" ] || [ "${IDENTITY}" = "-" ]; then
  echo "note: no code-signing identity; skipping nested Strut codesign"
  exit 0
fi

TIMESTAMP_FLAG="--timestamp"
if [ "${CONFIGURATION:-}" = "Debug" ]; then
  TIMESTAMP_FLAG="--timestamp=none"
fi

sign_exec() {
  codesign --force --sign "${IDENTITY}" --entitlements "${ENTITLEMENTS}" \
    --options runtime ${TIMESTAMP_FLAG} "$1"
}

sign_lib() {
  codesign --force --sign "${IDENTITY}" \
    --options runtime ${TIMESTAMP_FLAG} "$1"
}

sign_exec "${NATIVE}/node"
sign_lib "${NATIVE}/sherpa-onnx.node"
sign_lib "${NATIVE}/libonnxruntime.dylib"
sign_lib "${NATIVE}/libsherpa-onnx-c-api.dylib"

echo "Signed nested Strut Mach-O with ${IDENTITY}"

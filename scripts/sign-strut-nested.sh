#!/bin/sh
# Sign nested Strut Mach-O after the Embed Strut Helper copy phase.
# Team ID 8297M44YTW (DEVELOPMENT_TEAM). Hardened runtime, no --deep.
# Helper entitlements: sandbox inherit + cs.allow-jit (StrutNode.entitlements).
# Do NOT pass com.apple.security.cs.disable-library-validation.
# Do NOT pass cs.allow-unsigned-executable-memory unless a signed Apple Silicon
# spike shows V8 isolate setup dying (helper only, never the parent).
#
# This is the codeSignOnCopy stand-in for nested Mach-O inside the copied
# folder (Copy Files cannot both copy the tree and codeSignOnCopy individual
# nested files without duplicate-output errors).
#
# Invoked from the Sphinx target "Sign Strut Nested Code" run-script phase.

set -euo pipefail

HELPER="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/Strut"
ENTITLEMENTS="${SRCROOT}/com.stakwork.sphinx.desktop/StrutNode.entitlements"
SHERPA="${HELPER}/node_modules/sherpa-onnx-darwin-arm64"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"

if [ ! -d "${HELPER}" ]; then
  echo "error: Strut helper missing at ${HELPER}" >&2
  exit 1
fi
if [ ! -f "${HELPER}/node" ] || [ ! -d "${SHERPA}" ]; then
  echo "error: nested Strut Mach-O missing under ${HELPER}" >&2
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

sign_exec "${HELPER}/node"
sign_lib "${SHERPA}/sherpa-onnx.node"
sign_lib "${SHERPA}/libonnxruntime.dylib"
sign_lib "${SHERPA}/libsherpa-onnx-c-api.dylib"
sign_lib "${SHERPA}/libsherpa-onnx-cxx-api.dylib"

echo "Signed nested Strut Mach-O with ${IDENTITY}"

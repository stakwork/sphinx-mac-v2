#!/bin/sh
# Layout / contract checks for the vendored Strut helper.
# Run from the repo root. Does not spawn Node (this tree is darwin-arm64).

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HELPER="${ROOT}/com.stakwork.sphinx.desktop/Supporting Files/Strut"
ENT="${ROOT}/com.stakwork.sphinx.desktop/StrutNode.entitlements"
PARENT="${ROOT}/com.stakwork.sphinx.desktop/com_stakwork_sphinx_desktop.entitlements"

fail() { echo "error: $*" >&2; exit 1; }

NATIVE="${HELPER}/native"

[ -f "${HELPER}/desktop.js" ] || fail "missing desktop.js (frozen entry)"
[ -f "${NATIVE}/node" ] || fail "missing arm64 node"
[ -f "${NATIVE}/sherpa-onnx.node" ] || fail "missing sherpa-onnx.node"
[ -f "${NATIVE}/libonnxruntime.dylib" ] || fail "missing libonnxruntime.dylib"
[ -f "${NATIVE}/libsherpa-onnx-c-api.dylib" ] || fail "missing libsherpa-onnx-c-api.dylib"
[ -f "${ENT}" ] || fail "missing StrutNode.entitlements"

# native/ must hold ONLY Mach-O — codesign refuses to seal the outer app if
# any OTHER top-level directory under Contents/ is named "Helpers" (see
# scripts/sign-strut-nested.sh), and mixing a plain resource into native/
# defeats the point of isolating strut's signable binaries in one place.
for f in "${NATIVE}"/*; do
  base="$(basename "${f}")"
  case "${base}" in
    node|sherpa-onnx.node|libonnxruntime.dylib|libsherpa-onnx-c-api.dylib) ;;
    *) fail "unexpected file in native/: ${base}" ;;
  esac
done

# Mach-O 64-bit little-endian, CPU_TYPE_ARM64 (0x0100000c)
python3 - "${NATIVE}/node" <<'PY'
import struct, sys
path = sys.argv[1]
with open(path, "rb") as f:
    data = f.read(8)
if len(data) < 8:
    sys.exit("node too small")
magic, cputype = struct.unpack("<II", data)
if magic != 0xFEEDFACF or cputype != 0x0100000C:
    sys.exit(f"node is not thin arm64 Mach-O (magic=0x{magic:08x} cputype=0x{cputype:08x})")
print("node: thin arm64 Mach-O OK")
PY

for key in \
  com.apple.security.app-sandbox \
  com.apple.security.inherit \
  com.apple.security.cs.allow-jit
do
  grep -q "$key" "${ENT}" || fail "helper entitlements missing $key"
done

if grep -q "<key>com.apple.security.cs.disable-library-validation</key>" "${ENT}" "${PARENT}"; then
  fail "disable-library-validation must not be used"
fi

echo "Strut helper layout + entitlements OK"
echo "Frozen argv: Contents/Strut/native/node Contents/Strut/desktop.js"
echo "Ready-line timeout: 10s (see StrutProcessController.defaultReadyLineTimeout)"

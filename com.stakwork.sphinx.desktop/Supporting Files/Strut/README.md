# Bundled Strut helper

Vendored from [stakwork/strut](https://github.com/stakwork/strut) `v0.1.1` (`strut-darwin-arm64.tar.gz`) plus official Node `v22.23.2` darwin-arm64 (`bin/node` only).

Layout lands at `Sphinx.app/Contents/Helpers/Strut` via the **Embed Strut Helper** Copy Files phase: Wrapper (`dstSubfolderSpec = 1` → `Contents`) + `dstPath = Helpers`, copying the `Strut` folder (Xcode's Helper Executables destination with `dstPath = Strut`). Nested Mach-O are re-signed by **Sign Strut Nested Code** (`scripts/sign-strut-nested.sh`) — equivalent to `codeSignOnCopy` on `node` / `sherpa-onnx.node` / dylibs, and the only way to attach `StrutNode.entitlements` to `node`. Do not `codeSignOnCopy` the folder itself (it is not a bundle).

## Frozen spawn (StrutProcessController)

```
argv:  <Helpers/Strut>/node  <Helpers/Strut>/desktop.js
cwd:   <Helpers/Strut>
env:   HOME + TMPDIR = Application Support/Sphinx/Strut
       no DYLD_*
```

Ready line (stdout, one JSON object): `{"event":"ready","port":<int>,"host":"127.0.0.1","key":"<per-launch>"}`.
`GET /health` is unauthenticated. `/audio/*` uses `Authorization: Bearer <key>`.

Entry file is **`desktop.js`** (strut desktop launcher). Not `strut.js`. The `strut` file is a shell wrapper for humans; the host must spawn Node + `desktop.js`.

Ready-line timeout stays **10s**. Strut documents ~1s recognizer cold-start after the process is up; Node + sherpa-onnx-node load is typically 1–3s on Apple Silicon. Re-measure on a signed arm64 build if cold start exceeds ~5s.

## Signing / entitlements

- Team ID `8297M44YTW` (same as `DEVELOPMENT_TEAM`).
- Nested Mach-O (`node`, `sherpa-onnx.node`, `libonnxruntime.dylib`, `libsherpa-onnx-c-api.dylib`, `libsherpa-onnx-cxx-api.dylib`) use `codeSignOnCopy` plus the **Sign Strut Nested Code** script, which applies `StrutNode.entitlements` to `node`.
- Helper entitlements (`StrutNode.entitlements`, ticket T3): `app-sandbox` + `inherit` + `cs.allow-jit`. **No** `cs.disable-library-validation`. **No** `cs.allow-unsigned-executable-memory` unless a signed Apple Silicon spike shows V8 isolate setup dying without it (helper only, never the parent).

## Spike status

This Linux/CI environment cannot codesign, notarize, or spawn the arm64 Mach-O under App Sandbox. On Apple Silicon, confirm: child starts with inherit+allow-jit, sherpa-onnx-darwin-arm64 loads (`GET /audio/models` `available: true`), ready line within 10s, `/health` 2xx, no Gatekeeper prompt on a notarized archive.

# Bundled Strut helper

Vendored from [stakwork/strut](https://github.com/stakwork/strut) `v0.1.1` (`dist-desktop/strut-darwin-arm64.tar.gz`, relocated-native build) plus official Node `v22.23.2` darwin-arm64 (`native/node` only — Node ships separately, strut's tarball does not include it).

Layout lands at `Sphinx.app/Contents/Strut` via the **Embed Strut Helper** Copy Files phase: Wrapper (`dstSubfolderSpec = 1`) + `dstPath = Contents`, copying the `Strut` folder. Nested Mach-O are signed by **Sign Strut Nested Code** (`scripts/sign-strut-nested.sh`) — the only way to attach `StrutNode.entitlements` to `node`.

## Why `Contents/Strut`, not `Contents/Helpers/Strut`

`Contents/Helpers/` is a reserved bundle location (like `Frameworks/`, `PlugIns/`, `XPCServices/`) — macOS's codesign requires *everything* under it to be independently-signed nested code and rejects any plain resource file placed there outright, **regardless of whether a Mach-O is anywhere nearby**. Confirmed with minimal repros while packaging this branch:

- A lone `Contents/Helpers/x/resource.txt`, no Mach-O involved at all, fails to seal the outer app ("code object is not signed at all").
- The identical mixed tree (Mach-O + resources, same directory, no isolation) seals fine under `Contents/Strut/` or any other non-reserved top-level `Contents/` directory name.

Earlier iterations of this packaging tried `--deep` code-signing (unreliable — false-positives on `node_modules` packages whose directory name merely looks executable-ish, e.g. `bignumber.js`) and `CodeSignOnCopy` on the folder-reference copy (silent no-op — Xcode only signs-on-copy build-file entries it recognizes as products, not arbitrary folders). Neither was the actual fix. **Just avoid the `Helpers` path segment.**

## Why `native/` still exists

Not required to satisfy the rule above, but kept because strut's own packaging (`scripts/package-desktop.mjs`'s `relocateNative`) already isolates every Mach-O it ships into one binaries-only directory:

- `native/node`, `native/sherpa-onnx.node`, `native/libonnxruntime.dylib`, `native/libsherpa-onnx-c-api.dylib` — nothing else should ever be added to `native/`.
- `sherpa-onnx-node/addon-static-import.js` is patched upstream to `require('../../native/sherpa-onnx.node')` directly, instead of resolving a `sherpa-onnx-<platform>` optional dependency via `os.arch()`.
- `node` isn't part of strut's tarball, so vendoring it into `native/` (alongside strut's own relocated binaries) is on this side — done by hand when re-vendoring; see below.

## Re-vendoring (bumping the strut version)

1. Download the new `strut-darwin-arm64.tar.gz` and extract it over `Supporting Files/Strut`, **except** don't let it delete/replace `native/node` (Node isn't part of the tarball).
2. Confirm the extracted tree still puts every Mach-O under `native/` (`find . -path ./native -prune -o -type f -print | xargs file | grep -i mach-o` from inside the `Strut` folder should print nothing).
3. Copy `native/node` back in from the previous vendored copy (or re-download from nodejs.org if bumping Node too) and `chmod +x`.
4. Update `VERSION` in this folder.
5. Run `scripts/verify-strut-helper.sh`, then rebuild the Sphinx target and confirm `CodeSign Sphinx.app` succeeds with the project's normal (non-`--deep`) signing.

## Frozen spawn (StrutProcessController)

```
argv:  <Strut>/native/node  <Strut>/desktop.js
cwd:   <Strut>
env:   HOME + TMPDIR = Application Support/Sphinx/Strut
       no DYLD_*
```

Ready line (stdout, one JSON object): `{"event":"ready","port":<int>,"host":"127.0.0.1","key":"<per-launch>"}`.
`GET /health` is unauthenticated. `/audio/*` uses `Authorization: Bearer <key>`.

Entry file is **`desktop.js`** (strut desktop launcher). Not `strut.js`. The `strut` file is a shell wrapper for humans; the host must spawn Node + `desktop.js`.

Ready-line timeout stays **10s**. Strut documents ~1s recognizer cold-start after the process is up; Node + sherpa-onnx-node load is typically 1–3s on Apple Silicon. Re-measure if cold start exceeds ~5s.

## Signing / entitlements

- Team ID `8297M44YTW` (same as `DEVELOPMENT_TEAM`).
- Nested Mach-O (`native/node`, `native/sherpa-onnx.node`, `native/libonnxruntime.dylib`, `native/libsherpa-onnx-c-api.dylib`) are signed by the **Sign Strut Nested Code** script, which applies `StrutNode.entitlements` to `node`.
- Helper entitlements (`StrutNode.entitlements`, ticket T3): `app-sandbox` + `inherit` + `cs.allow-jit`. **No** `cs.disable-library-validation`. **No** `cs.allow-unsigned-executable-memory` unless a signed Apple Silicon spike shows V8 isolate setup dying without it (helper only, never the parent).

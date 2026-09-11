# sphinx-mac-v2

# Setup

## Github Large Files

- This repository uses git large files. Run the following commands to get the full large files:

```
brew install git-lfs
git lfs install
git lfs pull
```

## CocoaPods

- This repository uses CocoaPods submodules. After cloning run:

```
pod install
```


## Giphy

- Set a valid API KEY for Giphy library on info.plist file

## Branch

This repository uses ```develop``` branch as base branch for development. Master is not up to date.

## Strut helper (dictation)

The app bundle ships a local Strut process at `Contents/Helpers/Strut` (arm64 Node `v22.23.2` + [strut v0.1.1](https://github.com/stakwork/strut/releases/tag/v0.1.1) + `sherpa-onnx-darwin-arm64`). `StrutProcessController` spawns:

```
node  desktop.js
```

from that folder (`HOME`/`TMPDIR` under Application Support). Nested Mach-O are signed with Team ID `8297M44YTW` by the **Sign Strut Nested Code** build phase (`scripts/sign-strut-nested.sh`) using `StrutNode.entitlements` (sandbox inherit + `cs.allow-jit`). Do not add `cs.disable-library-validation`.

Vendored binaries are Git LFS. After clone: `git lfs pull`.

Layout / contract check (no spawn): `scripts/verify-strut-helper.sh`.

## Release / notarization

There is no separate Strut notarization pipeline. Archive and notarize **Sphinx.app** as usual (Xcode Organizer or `notarytool`). Nested code under `Contents/Helpers/Strut` is already signed with `--options runtime` during the app build; notarization covers the whole bundle, including `node`, `sherpa-onnx.node`, and the sherpa dylibs. Confirm on Apple Silicon: no Gatekeeper prompt, ready JSON line within 10s, `GET /health` 2xx.

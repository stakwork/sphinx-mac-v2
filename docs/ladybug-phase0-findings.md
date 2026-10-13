# LadybugDB Phase 0 findings (Mac + iOS)

Date: 2026-10-13. Branch: `tt/feature/graph-db`. Covers both `sphinx-mac-v2`
and `sphinx-ios-v2` (this file is duplicated in both repos). The temporary
test harness that produced these results (`LadybugPhase0Test.swift` on each
platform, hooked into app launch behind a `LADYBUG_PHASE0_STEP` env var) has
been removed after Phase 0 sign-off; this doc is what's left of it.

Everything below was run against the real, signed app binary directly (Mac:
a Release build launched from Terminal; iOS: `xcrun devicectl` against a
real connected device, not the Simulator — see §4), not `swift test`, since
the whole point of Phase 0 was to exercise the actual embedding/signing and
sandboxing a unit test bundle wouldn't faithfully reproduce.

## 1. How iOS is built

Not a local path, not a fork, not a patched manifest. The repo vendors the
**fully generated C++ source tree** at `LocalPackages/swift-ladybug/`
(2,620 files, confirmed tracked by git — not gitignored), wired in as an
`XCLocalSwiftPackageReference` with a **project-relative** path in
`sphinx.xcodeproj/project.pbxproj`. A clean clone and CI get exactly what
was built here. This is what the upstream README's "source builds only
work from a full clone" caveat is sidestepped by: the vendoring makes this
repo itself the full clone.

Pin: `swift-ladybug` is at upstream commit `c071a7ca931241651c4d1bbc19c8780401f58c3f`
(same commit Peel vendors, per its own docs). `git describe` on that commit:
`v0.16.1-6-gc071a7c` — 6 commits past the last upstream tag, on `main`.
Upstream has exactly two tags (`v0.16.1`, `v0.12.2`); no tag exists yet that
includes the "default to prebuilt liblbug" commit this vendoring depends on.
The native engine binary itself (from the separate `LadybugDB/ladybug`
repo, fetched via GitHub releases on Mac) *is* a clean tagged release:
`v0.21.2`.

## 2. The `swift-docc-plugin` pin

Not an issue here, verified rather than assumed:
- `LocalPackages/swift-ladybug/Package.swift` already declares it correctly
  (`from: "1.4.5"`, not `branch:`), and its own `Package.resolved` resolves
  it to a clean `1.5.0` tag.
- The **top-level app build never resolves `swift-docc-plugin` at all** —
  zero references in the top-level `Package.resolved` or in Xcode's
  `workspace-state.json`. It's a doc-generation-only dependency of the inner
  package; a plain `xcodebuild build` never touches it.
- Confirmed on a fully cold rebuild (wiped `DerivedData`, `~/Library/Caches/org.swift.swiftpm`,
  and the inner package's own `.build`) — resolution succeeded purely from
  committed state, nothing machine-local was propping it up.

## 3. Clean-machine build — the Mac weak point, confirmed by reading the script

Did a real wipe-everything-and-rebuild on both platforms (not just a
Debug→Release switch). Hit one transient, unrelated LiveKit submodule clone
flake on iOS the first time; retried, succeeded.

**Found and fixed this session** (see `a1f1b7fa` and `2f88c8c1` on `master`,
merged into this branch): the "Download liblbug" build phase's
`install_name_tool` fix-up only patched the *first* stale OpenSSL reference
it found and was skipped entirely once the vendored copies were already
cached — this caused real `dyld`/"different Team IDs" launch crashes.
Fixed to loop over every distinct reference across all architecture slices,
unconditionally.

**Found, not yet fixed — the actual "weakest point"**: in that same build
phase, when no Homebrew `openssl@3` is found anywhere (`/opt/homebrew`,
`/usr/local`, `brew --prefix`), the script prints a `warning:` to stderr and
**returns success** (no `exit 1`). The downstream "Embed liblbug" phase then
finds nothing to copy and **also** just warns and returns success. Net
effect: a CI runner or dev machine without Homebrew's `openssl@3` gets
`BUILD SUCCEEDED`, and the resulting `Sphinx.app` crashes on launch with a
dyld error that gives no hint the real cause is a missing Homebrew package.
**Not yet fixed** — turning those two warnings into hard failures (or
better, a clear upfront check with an actionable message) is a small,
separate follow-up.

iOS has no equivalent risk: the engine compiles straight into the app's own
binary (no separate dylib to embed or sign at all).

## 4. iOS runtime, on a real device

Simulator is currently blocked for the *whole* `sphinx` scheme on Apple
Silicon by a pre-existing, unrelated issue: `universal-sphinxrs.a` (the Rust
core, last touched well before this branch) has only a device-tagged arm64
slice, not a Simulator one, which breaks linking the Notification Service
Extension. Nothing to do with Ladybug; worth its own ticket.

Ran the full round trip on a real connected iPhone instead
(`xcrun devicectl device process launch --console -e '{"...":"..."}'`, with
`devicectl device process signal --signal 9` as the device equivalent of
`kill -9`): schema creation, 2 nodes + 1 edge insert, `MATCH` query, a
genuine process relaunch confirming persistence, export/import with
matching counts. All passed. The export's file layout
(`schema.cypher`, `index.cypher`, `nodes_*.parquet`, `rels_*.parquet`) has
no `macro.cypher`/`copy.cypher` on either platform — contrary to some
docs pages; may describe an older/different version.

## 5. Build time and app size

- **iOS, from absolute zero cache**: **5m 14s** wall-clock for the whole
  app, including compiling all 2,620 vendored C++ files.
- **Size**: total Debug device `.app` is 314MB, dominated by unrelated SDKs
  (Jitsi 38MB, VLC 34MB, WebRTC ~21MB). Isolating Ladybug: `cxx-ladybug.o`,
  the linked engine object, is **121.6MB** — the single largest compiled
  SPM package object in the app, ~6x the next largest. Caveat: this is a
  Debug/device intermediate (full debug info, pre-strip); a Release/Archive
  IPA would be smaller after thinning — not measured here.
- **Mac, for contrast**: near-zero added build time (download + lipo +
  codesign only, no compilation), ~55MB added to the bundle
  (`liblbug.0.dylib` 42.9MB + `libcrypto.3.dylib` 9.7MB + `libssl.3.dylib`
  1.8MB).

## 6. Phase 0b — robustness

**Many small writes vs. bulk load**: individual single-row `CREATE`s are
**>2,000x slower** than bulk `COPY` — 213 rows/s (Mac) and 185 rows/s (iOS)
vs. >500,000 rows/s via bulk load on both. Directly relevant to an agent
doing "remember this fact" one row at a time; any real design should batch
where it can.

**iOS main-thread gotcha** (a harness bug, but worth generalizing): running
the write loop synchronously during app launch got the process **killed by
iOS's own launch watchdog** around ~20s, no Ladybug error at all. Any real
calling code must do this kind of work off the main thread.

**Crash mid-write**:
- Mac, killed at row 250 (exact, via a self-`kill(getpid(), SIGKILL)` to
  remove any external-timing race — an externally-timed kill raced against
  devicectl's console-log latency on iOS and landed hundreds of rows past
  the intended point, so the self-kill approach is the one to reuse):
  clean reopen, `count()` matches a full row scan exactly (251/251).
- iOS, same row 250, same checkpoint cadence: **identical** — 251/251,
  clean. At matched conditions the platforms behave the same.
- iOS, killed much later (~7,175 rows, ~71 checkpoints): database became
  **unable to reopen at all** — `Cannot open file crashwrite.lbug.shadow:
  No such file or directory`. Real finding, but not yet a platform
  conclusion: since matched conditions showed no difference, this points at
  "many checkpoint cycles before a hard kill" as the risk factor, not iOS
  specifically — **Mac was not tested at a similarly high checkpoint count,
  that's the next thing to check** before concluding anything platform-specific.
- A `.wal` sidecar file left over from an earlier killed run can make the
  *next* run's "delete and recreate" fail with a confusing
  `databaseInitializationFailed` unless the sidecar is deleted too, not just
  the main `.lbug` file. (Harness bug, not a Ladybug bug, but a real
  operational detail for anything that resets a Ladybug file.)

**Concurrent writers**:
- Mac: a second process is refused cleanly at `Database()` init —
  `Could not set lock on file ... Resource temporarily unavailable`,
  pointing at Ladybug's own concurrency docs. No corruption, no silent data
  loss.
- iOS: **structurally different, not tested the same way** — iOS enforces
  single-instance per bundle ID at the OS level, so "two processes of the
  same app" isn't constructible the way it is on Mac (a second
  `devicectl launch` just no-ops against the first). The real analogous
  risk on iOS is the main app and the **Notification Service Extension**
  (which this project has) both touching the same file via the shared
  app-group container — **not tested**, and the right follow-up if
  concurrent access matters for the real design.

## Open follow-ups

1. Fix the Mac "no Homebrew openssl@3" silent-success gap (§3).
2. Check whether Mac has the same "many checkpoints before a hard kill"
   exposure iOS showed (§6) — run Mac's crash test at a comparable
   checkpoint count.
3. Test main-app ↔ Notification-Extension concurrent access on iOS (§6).
4. Get a Release/Archive IPA size number for iOS, not just Debug (§5).
5. Decide what to do about the `swift-ladybug` version pin not being on an
   upstream tag (§1) — accept the commit pin as-is, or ask upstream to cut
   one.

# Context

## Swift 6 Concurrency Compliance

All Swift code in this repository should follow Swift 6 concurrency conventions:

- **Concurrency safety**: Prefer `async`/`await` over completion handlers or manual `DispatchQueue` juggling where feasible.
- **Actor isolation**: Apply `@MainActor` annotations on UI-facing types/methods; use explicit actor boundaries for shared mutable state instead of locks or `DispatchSemaphore` where appropriate.
- **Sendable conformance**: Types crossing concurrency boundaries should conform to `Sendable`. Use `@unchecked Sendable` only when truly justified, and always include a comment explaining why.
- **No data races**: Avoid shared mutable state across actors/tasks without proper isolation. Do not capture non-`Sendable` types in `Task { }` closures. Avoid unstructured concurrency that could cause races.
- **Strict concurrency checking**: Write code as if `SWIFT_STRICT_CONCURRENCY=complete` is enabled — it should compile cleanly without warnings about actor isolation, sendability, or non-isolated access.

## Swift File Registration

`sphinx-mac-v2` is a Swift/Xcode project with its primary source tree under `com.stakwork.sphinx.desktop/`. Any new `.swift` file added to the project **must** have a corresponding entry in the project's `project.pbxproj`, specifically:

- A **`PBXFileReference`** entry for the file.
- A **`PBXBuildFile`** entry linking it to the correct target's Sources build phase.
- **Group membership** so the file appears in the correct folder in Xcode's navigator.
- A **target membership check** — `com.stakwork.sphinx.desktopTests` is a separate target from the main desktop app, so files must be added to the correct target(s) (main app vs. test target vs. extension target).

Failing to register a new `.swift` file in `project.pbxproj` will silently exclude it from the build.

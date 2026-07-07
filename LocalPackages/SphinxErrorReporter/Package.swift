// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SphinxErrorReporter",
    platforms: [
        .iOS(.v14),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SphinxErrorReporter",
            targets: ["SphinxErrorReporter"]
        ),
    ],
    targets: [
        .target(
            name: "SphinxErrorReporter",
            dependencies: [],
            path: "Sources/SphinxErrorReporter"
        ),
        .testTarget(
            name: "SphinxErrorReporterTests",
            dependencies: ["SphinxErrorReporter"],
            path: "Tests/SphinxErrorReporterTests"
        ),
    ]
)

// swift-tools-version: 5.9
//
// Swift Package Manager resolves packages from the repository root, so every Swift
// product in this monorepo is declared here, with target paths pointing into `swift/`.
// To add another product (for example the Grid SwiftUI renderer), append a library to
// `products` and its targets to `targets`.
import PackageDescription

/// Strict concurrency for every Swift target, so the code also builds in Swift 6 language mode.
let strictConcurrency: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

let package = Package(
    name: "NullDull",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        // Workspace API key client: Grid delivery, read-only Memory and Locale export. Foundation only.
        .library(name: "NullDull", targets: ["NullDull"]),
    ],
    targets: [
        .target(
            name: "NullDull",
            path: "swift/Sources/NullDull",
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "NullDullTests",
            dependencies: ["NullDull"],
            path: "swift/Tests/NullDullTests",
            swiftSettings: strictConcurrency
        ),
    ]
)

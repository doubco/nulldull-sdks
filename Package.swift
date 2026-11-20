// swift-tools-version: 5.9
//
// Swift Package Manager resolves packages from the repository root, so every Swift
// product in this monorepo is declared here, with target paths pointing into `swift/`.
// To add another product, append a library to `products` and its targets to `targets`.
//
// Platform minimums apply to the whole package and are set by the `NullDull` SDK. The Grid
// renderer needs newer releases only for SwiftUI (`Layout`, `Grid`, `ProposedViewSize`), so
// `NullDullGridUI` declares them with `@available(iOS 16, macOS 13, tvOS 16, *)` instead of
// raising them here. `NullDullGrid` builds at the package minimums. `NullDullGridUI` does not
// support watchOS (it uses AVKit's player), and the Grid products need a Swift 6 toolchain.
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
        // Grid document model, validation, layout engine and public content client. Foundation only.
        .library(name: "NullDullGrid", targets: ["NullDullGrid"]),
        // Grid SwiftUI renderer.
        .library(name: "NullDullGridUI", targets: ["NullDullGridUI"]),
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
        .target(
            name: "NullDullGrid",
            path: "swift/Sources/NullDullGrid",
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "NullDullGridUI",
            dependencies: ["NullDullGrid"],
            path: "swift/Sources/NullDullGridUI",
            swiftSettings: strictConcurrency,
            linkerSettings: [.linkedFramework("AVKit"), .linkedFramework("AVFoundation")]
        ),
        .testTarget(
            name: "NullDullGridTests",
            dependencies: ["NullDullGrid"],
            path: "swift/Tests/NullDullGridTests",
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "NullDullGridUITests",
            dependencies: ["NullDullGridUI", "NullDullGrid"],
            path: "swift/Tests/NullDullGridUITests",
            swiftSettings: strictConcurrency
        ),
    ]
)

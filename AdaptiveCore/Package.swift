// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AdaptiveCore",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        .macOS(.v26), // host platform for `swift test` (Observation/@Observable need macOS 14+)
    ],
    products: [
        .library(name: "AdaptiveCore", targets: ["AdaptiveCore"]),
    ],
    targets: [
        .target(name: "AdaptiveCore"),
        .testTarget(name: "AdaptiveCoreTests", dependencies: ["AdaptiveCore"]),
    ]
)

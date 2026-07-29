// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "UsageBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "UsageBar", targets: ["UsageBar"]),
        .library(name: "UsageBarCore", targets: ["UsageBarCore"]),
    ],
    targets: [
        .target(
            name: "UsageBarCore"),
        .executableTarget(
            name: "UsageBar",
            dependencies: ["UsageBarCore"]),
        .testTarget(
            name: "UsageBarCoreTests",
            dependencies: ["UsageBarCore"])
    ]
)

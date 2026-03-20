// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Untouchable",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "Untouchable",
            dependencies: [],
            path: "Untouchable"
        )
    ]
)

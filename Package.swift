// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CapBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CapBar", targets: ["CapBar"])
    ],
    targets: [
        .executableTarget(
            name: "CapBar",
            resources: [
                .process("Resources")
            ]
        )
    ]
)

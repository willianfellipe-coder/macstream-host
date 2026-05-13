// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "MacStreamHost",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MacStreamCore",
            targets: ["MacStreamCore"]
        ),
        .executable(
            name: "MacStreamHostApp",
            targets: ["MacStreamHostApp"]
        ),
        .executable(
            name: "macstreamctl",
            targets: ["macstreamctl"]
        )
    ],
    targets: [
        .target(
            name: "MacStreamCore",
            path: "src/MacStreamCore"
        ),
        .executableTarget(
            name: "MacStreamHostApp",
            dependencies: ["MacStreamCore"],
            path: "src/MacStreamHostApp"
        ),
        .executableTarget(
            name: "macstreamctl",
            dependencies: ["MacStreamCore"],
            path: "src/macstreamctl"
        ),
        .testTarget(
            name: "MacStreamCoreTests",
            dependencies: ["MacStreamCore"],
            path: "tests/MacStreamCoreTests"
        )
    ]
)

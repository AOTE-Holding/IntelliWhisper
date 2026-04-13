// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "IntelliWhisper",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "0.12.0"),
        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", exact: "2.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "IntelliWhisper",
            dependencies: [
                "WhisperKit",
                "SwiftyBeaver",
            ],
            path: "Sources/IntelliWhisper",
            resources: [
                .process("Assets"),
            ]
        ),
    ]
)
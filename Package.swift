// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "DerFluisterer",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "DerFluisterer", targets: ["DerFluisterer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.12.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "DerFluisterer",
            dependencies: [
                "WhisperKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .executableTarget(
            name: "DerFluistererApp",
            dependencies: ["DerFluisterer"]
        ),
        .executableTarget(
            name: "HotkeyTestCLI",
            dependencies: ["DerFluisterer"],
            path: "Tools/HotkeyTestCLI"
        ),
        .executableTarget(
            name: "AudioTestCLI",
            dependencies: ["DerFluisterer"],
            path: "Tools/AudioTestCLI"
        ),
        .executableTarget(
            name: "TranscribeTestCLI",
            dependencies: ["DerFluisterer"],
            path: "Tools/TranscribeTestCLI"
        ),
        .testTarget(
            name: "DerFluistererTests",
            dependencies: ["DerFluisterer"]
        ),
    ]
)

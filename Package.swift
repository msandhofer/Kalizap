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
            name: "CDeepFilter",
            path: "Sources/CDeepFilter",
            exclude: ["lib"],
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "Sources/CDeepFilter/lib",
                    "-ldf",
                ]),
            ]
        ),
        .target(
            name: "DerFluisterer",
            dependencies: [
                "WhisperKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .executableTarget(
            name: "DerFluistererApp",
            dependencies: ["DerFluisterer"],
            exclude: ["Info.plist"]
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
        .executableTarget(
            name: "TextInsertTestCLI",
            dependencies: ["DerFluisterer"],
            path: "Tools/TextInsertTestCLI"
        ),
        .executableTarget(
            name: "CorrectorTestCLI",
            dependencies: ["DerFluisterer"],
            path: "Tools/CorrectorTestCLI"
        ),
        .executableTarget(
            name: "WhisperModelTestCLI",
            dependencies: ["DerFluisterer", "WhisperKit"],
            path: "Tools/WhisperModelTestCLI"
        ),
        .executableTarget(
            name: "VoiceProcessingTestCLI",
            dependencies: ["DerFluisterer", "CDeepFilter"],
            path: "Tools/VoiceProcessingTestCLI"
        ),
        .testTarget(
            name: "DerFluistererTests",
            dependencies: ["DerFluisterer"]
        ),
    ]
)

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
        .package(url: "https://github.com/soniqo/speech-swift", branch: "main"),
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
            name: "CWhisper",
            path: "Sources/CWhisper",
            exclude: ["lib"],
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "Sources/CWhisper/lib",
                    "-lwhisper",
                ]),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("CoreML"),
                .linkedFramework("Foundation"),
            ]
        ),
        .target(
            name: "DerFluisterer",
            dependencies: [
                "CDeepFilter",
                "CWhisper",
                "WhisperKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .executableTarget(
            name: "DerFluistererApp",
            dependencies: ["DerFluisterer"],
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/DeepFilterNet3_onnx.tar.gz"),
            ]
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
        .executableTarget(
            name: "ToastTestCLI",
            dependencies: [],
            path: "Tools/ToastTestCLI"
        ),
        .executableTarget(
            name: "InsertDelayTest",
            dependencies: ["DerFluisterer"],
            path: "Tools/InsertDelayTest"
        ),
        .target(
            name: "STTTestCommon",
            path: "Tools/STTTestCommon"
        ),
        .executableTarget(
            name: "WhisperCppTestCLI",
            dependencies: [
                "DerFluisterer",
                "STTTestCommon",
                .product(name: "SpeechVAD", package: "speech-swift"),
            ],
            path: "Tools/WhisperCppTestCLI"
        ),
        .executableTarget(
            name: "SpeechSwiftTestCLI",
            dependencies: [
                "STTTestCommon",
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
            ],
            path: "Tools/SpeechSwiftTestCLI"
        ),
        .testTarget(
            name: "DerFluistererTests",
            dependencies: ["DerFluisterer"]
        ),
        .testTarget(
            name: "STTTestCommonTests",
            dependencies: ["STTTestCommon"],
            path: "Tests/STTTestCommonTests"
        ),
    ]
)

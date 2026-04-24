// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DerFluisterer",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "DerFluisterer", targets: ["DerFluisterer"]),
    ],
    dependencies: [
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
            name: "DerFluisterer",
            dependencies: [
                "CDeepFilter",
            ]
        ),
        .executableTarget(
            name: "DerFluistererApp",
            dependencies: ["DerFluisterer"],
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/DeepFilterNet3_onnx.tar.gz"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/DerFluistererApp/Info.plist",
                ]),
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
        .executableTarget(
            name: "InsertDelayScreenshotTest",
            dependencies: ["DerFluisterer"],
            path: "Tools/InsertDelayScreenshotTest",
            exclude: ["screenshots"]
        ),
        .target(
            name: "STTTestCommon",
            path: "Tools/STTTestCommon"
        ),
        .executableTarget(
            name: "SpeechAnalyzerTestCLI",
            dependencies: [
                "STTTestCommon",
            ],
            path: "Tools/SpeechAnalyzerTestCLI",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Tools/SpeechAnalyzerTestCLI/Info.plist",
                ]),
            ]
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

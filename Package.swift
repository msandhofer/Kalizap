// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Kalizap",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "Kalizap", targets: ["Kalizap"]),
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
            name: "Kalizap",
            dependencies: [
                "CDeepFilter",
            ]
        ),
        .executableTarget(
            name: "KalizapApp",
            dependencies: ["Kalizap"],
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/DeepFilterNet3_onnx.tar.gz"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/KalizapApp/Info.plist",
                ]),
            ]
        ),
        .executableTarget(
            name: "HotkeyTestCLI",
            dependencies: ["Kalizap"],
            path: "Tools/HotkeyTestCLI"
        ),
        .executableTarget(
            name: "AudioTestCLI",
            dependencies: ["Kalizap"],
            path: "Tools/AudioTestCLI"
        ),
        .executableTarget(
            name: "TextInsertTestCLI",
            dependencies: ["Kalizap"],
            path: "Tools/TextInsertTestCLI"
        ),
        .executableTarget(
            name: "CorrectorTestCLI",
            dependencies: ["Kalizap"],
            path: "Tools/CorrectorTestCLI"
        ),
        .executableTarget(
            name: "VoiceProcessingTestCLI",
            dependencies: ["Kalizap", "CDeepFilter"],
            path: "Tools/VoiceProcessingTestCLI"
        ),
        .executableTarget(
            name: "ToastTestCLI",
            dependencies: [],
            path: "Tools/ToastTestCLI"
        ),
        .executableTarget(
            name: "InsertDelayTest",
            dependencies: ["Kalizap"],
            path: "Tools/InsertDelayTest"
        ),
        .executableTarget(
            name: "InsertDelayScreenshotTest",
            dependencies: ["Kalizap"],
            path: "Tools/InsertDelayScreenshotTest",
            exclude: ["screenshots"]
        ),
        .executableTarget(
            name: "PromptJailbreakTest",
            dependencies: [],
            path: "Tools/PromptJailbreakTest"
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
            name: "KalizapTests",
            dependencies: ["Kalizap"]
        ),
        .testTarget(
            name: "STTTestCommonTests",
            dependencies: ["STTTestCommon"],
            path: "Tests/STTTestCommonTests"
        ),
    ]
)

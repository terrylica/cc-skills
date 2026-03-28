// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "claude-tts-companion",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/nerzh/swift-telegram-sdk", from: "4.5.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/swhitty/FlyingFox", from: "0.26.0"),
        .package(url: "https://github.com/swiftlang/swift-testing", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "CSherpaOnnx",
            path: "Sources/CSherpaOnnx",
            publicHeadersPath: "include"
        ),
        .target(
            name: "CompanionCore",
            dependencies: [
                "CSherpaOnnx",
                .product(name: "SwiftTelegramBot", package: "swift-telegram-sdk"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "FlyingFox", package: "FlyingFox"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("AVFoundation"),
                .unsafeFlags([
                    "-L/Users/terryli/fork-tools/sherpa-onnx/build-swift-macos/install/lib",
                ]),
                .linkedLibrary("sherpa-onnx-c-api"),
                .linkedLibrary("sherpa-onnx-core"),
                .linkedLibrary("sherpa-onnx"),
                .linkedLibrary("onnxruntime"),
                .linkedLibrary("espeak-ng"),
                .linkedLibrary("piper_phonemize"),
                .linkedLibrary("ssentencepiece_core"),
                .linkedLibrary("ucd"),
                .linkedLibrary("kaldi-decoder-core"),
                .linkedLibrary("kaldi-native-fbank-core"),
                .linkedLibrary("sherpa-onnx-kaldifst-core"),
                .linkedLibrary("sherpa-onnx-fst"),
                .linkedLibrary("sherpa-onnx-fstfar"),
                .linkedLibrary("kissfft-float"),
                .linkedLibrary("c++"),
            ]
        ),
        .executableTarget(
            name: "claude-tts-companion",
            dependencies: ["CompanionCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "CompanionCoreTests",
            dependencies: [
                "CompanionCore",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)

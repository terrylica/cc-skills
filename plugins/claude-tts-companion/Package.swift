// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "claude-tts-companion",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/nerzh/swift-telegram-sdk", from: "4.5.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/swhitty/FlyingFox", from: "0.26.0"),
        .package(url: "https://github.com/terrylica/kokoro-ios.git", exact: "1.0.14"),
        .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", exact: "0.0.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
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
                .product(name: "KokoroSwift", package: "kokoro-ios"),
                .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
                .product(name: "MLX", package: "mlx-swift"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("AVFoundation"),
                .unsafeFlags([
                    "-L/Users/<you>/fork-tools/sherpa-onnx/build-swift-macos/install/lib",
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

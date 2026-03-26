// swift-tools-version: 6.0
import Foundation
import PackageDescription

let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
let sherpaOnnxPath = ProcessInfo.processInfo.environment["SHERPA_ONNX_PATH"]
    ?? "\(home)/fork-tools/sherpa-onnx/build-swift-macos/install"

let package = Package(
    name: "claude-tts-companion",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/nerzh/swift-telegram-sdk", from: "4.5.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/swhitty/FlyingFox", from: "0.26.0"),
    ],
    targets: [
        .target(
            name: "CSherpaOnnx",
            path: "Sources/CSherpaOnnx",
            cSettings: [
                .headerSearchPath("include"),
            ]
        ),
        .executableTarget(
            name: "claude-tts-companion",
            dependencies: [
                "CSherpaOnnx",
                .product(name: "SwiftTelegramBot", package: "swift-telegram-sdk"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "FlyingFox", package: "FlyingFox"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(sherpaOnnxPath)/lib",
                ]),
                .linkedLibrary("sherpa-onnx"),
                .linkedLibrary("onnxruntime"),
                .linkedLibrary("c++"),
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
            ]
        ),
    ]
)

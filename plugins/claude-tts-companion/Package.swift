// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "claude-tts-companion",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/nerzh/swift-telegram-sdk", from: "4.5.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/swhitty/FlyingFox", from: "0.26.0"),
        .package(url: "https://github.com/terrylica/kokoro-ios.git", exact: "1.0.13"),
        .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", exact: "0.0.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
    ],
    targets: [
        .executableTarget(
            name: "claude-tts-companion",
            dependencies: [
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
            ]
        ),
    ]
)

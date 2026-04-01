// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "dikto",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.1"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", revision: "2a296f145c3129fea4290bb6e4a0a5fb458efa06"),
        .package(url: "https://github.com/MrKai77/DynamicNotchKit", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "DiktoLib",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit"),
            ],
            path: "Sources/DiktoLib",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "dikto",
            dependencies: ["DiktoLib"],
            path: "Sources/Dikto"
        ),
        .executableTarget(
            name: "dikto-eval",
            dependencies: ["DiktoLib"],
            path: "eval/tool"
        ),
        .testTarget(
            name: "DiktoTests",
            dependencies: ["DiktoLib"],
            path: "Tests/DiktoTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)

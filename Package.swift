// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ru-wisper",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
    ],
    targets: [
        .target(
            name: "RuWisperLib",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
            ],
            path: "Sources/RuWisperLib",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "ru-wisper",
            dependencies: ["RuWisperLib"],
            path: "Sources/RuWisper"
        ),
        .testTarget(
            name: "RuWisperTests",
            dependencies: ["RuWisperLib"],
            path: "Tests/RuWisperTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)

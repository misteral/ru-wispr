// swift-tools-version: 6.0
import PackageDescription
import Foundation

let flavor = ProcessInfo.processInfo.environment["DIKTO_FLAVOR"] ?? "free"
let isProRU = flavor == "pro_ru"

let libSwiftSettings: [SwiftSetting] = isProRU
    ? [.define("DIKTO_PRO_RU")]
    : []

let package = Package(
    name: "dikto",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
        .package(url: "https://github.com/MrKai77/DynamicNotchKit", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "DiktoLib",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
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
            path: "Sources/Dikto",
            swiftSettings: libSwiftSettings
        ),
        .testTarget(
            name: "DiktoTests",
            dependencies: ["DiktoLib"],
            path: "Tests/DiktoTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)

if isProRU {
    if let libTarget = package.targets.first(where: { $0.name == "DiktoLib" }) {
        var settings = libTarget.swiftSettings ?? []
        settings.append(.define("DIKTO_PRO_RU"))
        libTarget.swiftSettings = settings
    }
}

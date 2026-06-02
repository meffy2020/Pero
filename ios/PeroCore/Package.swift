// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PeroCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PeroCore",
            targets: ["PeroCore"]
        )
    ],
    targets: [
        .target(
            name: "PeroCore"
        ),
        .testTarget(
            name: "PeroCoreTests",
            dependencies: ["PeroCore"]
        )
    ]
)

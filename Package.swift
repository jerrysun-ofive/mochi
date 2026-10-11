// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mochi",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MochiCore", targets: ["MochiCore"]),
        .library(name: "MochiAI", targets: ["MochiAI"]),
        .executable(name: "MochiApp", targets: ["MochiApp"]),
        .executable(name: "mochi-benchmark", targets: ["MochiBenchmark"]),
    ],
    targets: [
        .target(name: "MochiCore"),
        .target(name: "MochiAI", dependencies: ["MochiCore"]),
        .executableTarget(name: "MochiApp", dependencies: ["MochiCore", "MochiAI"]),
        .executableTarget(name: "MochiBenchmark", dependencies: ["MochiCore", "MochiAI"]),
        .testTarget(name: "MochiCoreTests", dependencies: ["MochiCore"]),
        .testTarget(
            name: "MochiAITests",
            dependencies: ["MochiAI", "MochiCore"]
        ),
        .testTarget(
            name: "MochiAppTests",
            dependencies: ["MochiApp", "MochiCore", "MochiAI"]
        ),
    ]
)

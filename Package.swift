// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Siming",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SimingServer", targets: ["SimingServer"]),
        .executable(name: "SimingGenerator", targets: ["SimingGenerator"]),
        .library(name: "SimingCore", targets: ["SimingCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.25.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.33.0"),
        .package(url: "https://github.com/apple/FHIRModels.git", from: "0.9.2"),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.11.0"),
        .package(url: "https://github.com/swift-server/swift-prometheus.git", from: "2.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "SimingServer",
            dependencies: [
                .target(name: "SimingCore"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "Prometheus", package: "swift-prometheus"),
            ]
        ),
        .target(
            name: "SimingCore",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "ModelsR4", package: "FHIRModels"),
            ]
        ),
        .executableTarget(
            name: "SimingGenerator",
            dependencies: []
        ),
        .testTarget(
            name: "SimingCoreTests",
            dependencies: [
                .target(name: "SimingCore"),
            ]
        ),
        .testTarget(
            name: "SimingIntegrationTests",
            dependencies: [
                .target(name: "SimingCore"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "ModelsR4", package: "FHIRModels"),
            ]
        ),
    ]
)

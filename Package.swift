// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloopFloop",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "FloopFloop",
            targets: ["FloopFloop"]
        ),
    ],
    targets: [
        .target(
            name: "FloopFloop",
            path: "Sources/FloopFloop"
        ),
        .testTarget(
            name: "FloopFloopTests",
            dependencies: ["FloopFloop"],
            path: "Tests/FloopFloopTests"
        ),
    ]
)

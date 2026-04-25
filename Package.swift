// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloopFloop",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
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

// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SojuKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SojuKit",
            targets: ["SojuKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftPackageIndex/SemanticVersion.git", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "SojuKit",
            dependencies: ["SemanticVersion"],
            path: "Sources/SojuKit"
        ),
        .testTarget(
            name: "SojuKitTests",
            dependencies: ["SojuKit"],
            path: "Tests/SojuKitTests"
        ),
    ]
)

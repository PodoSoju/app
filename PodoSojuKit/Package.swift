// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PodoSojuKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PodoSojuKit",
            targets: ["PodoSojuKit"]),
        .library(
            name: "SojuKit",
            targets: ["PodoSojuKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftPackageIndex/SemanticVersion.git", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "PodoSojuKit",
            dependencies: ["SemanticVersion"],
            path: "Sources/SojuKit"
        ),
        .testTarget(
            name: "PodoSojuKitTests",
            dependencies: ["PodoSojuKit"],
            path: "Tests/SojuKitTests"
        ),
    ]
)

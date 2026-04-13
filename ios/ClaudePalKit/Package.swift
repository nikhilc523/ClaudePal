// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudePalKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ClaudePalKit",
            targets: ["ClaudePalKit"]
        )
    ],
    targets: [
        .target(
            name: "ClaudePalKit"
        ),
        .testTarget(
            name: "ClaudePalKitTests",
            dependencies: ["ClaudePalKit"]
        )
    ]
)

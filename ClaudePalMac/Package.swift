// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ClaudePalMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ClaudePalMacCore", targets: ["ClaudePalMacCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.5.0"),
    ],
    targets: [
        .target(
            name: "ClaudePalMacCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),
        .testTarget(
            name: "ClaudePalMacCoreTests",
            dependencies: ["ClaudePalMacCore"]
        ),
    ]
)

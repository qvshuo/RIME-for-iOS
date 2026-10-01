// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "RimeSync",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "RimeSync",
            targets: ["RimeSync"]
        ),
    ],
    dependencies: [
        .package(path: "../RimeEngine"),
    ],
    targets: [
        .target(
            name: "RimeSync",
            dependencies: [
                .product(name: "RimeEngine", package: "RimeEngine"),
            ],
            path: "Sources/RimeSync"
        ),
    ]
)

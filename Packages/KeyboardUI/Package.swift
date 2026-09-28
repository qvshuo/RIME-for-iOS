// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "KeyboardUI",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "KeyboardUI",
            targets: ["KeyboardUI"]
        ),
    ],
    dependencies: [
        .package(path: "../RimeEngine"),
        .package(path: "../Models"),
        .package(path: "../Sync"),
    ],
    targets: [
        .target(
            name: "KeyboardUI",
            dependencies: [
                .product(name: "RimeEngine", package: "RimeEngine"),
                .product(name: "Models", package: "Models"),
                .product(name: "Sync", package: "Sync"),
            ],
            path: "Sources/KeyboardUI",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)

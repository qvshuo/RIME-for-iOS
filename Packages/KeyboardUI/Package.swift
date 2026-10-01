// swift-tools-version: 6.4

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
        .package(path: "../KeyboardModels"),
        .package(path: "../RimeSync"),
    ],
    targets: [
        .target(
            name: "KeyboardUI",
            dependencies: [
                .product(name: "RimeEngine", package: "RimeEngine"),
                .product(name: "KeyboardModels", package: "KeyboardModels"),
                .product(name: "RimeSync", package: "RimeSync"),
            ],
            path: "Sources/KeyboardUI",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)

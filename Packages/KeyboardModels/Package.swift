// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "KeyboardModels",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "KeyboardModels",
            targets: ["KeyboardModels"]
        ),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "KeyboardModels",
            path: "Sources/KeyboardModels"
        ),
    ]
)

// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RimeEngine",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "RimeEngine",
            targets: ["RimeEngine"]
        ),
    ],
    dependencies: [
        .package(path: "../KeyboardModels"),
    ],
    targets: [
        .binaryTarget(
            name: "librime",
            path: "../../Frameworks/librime.xcframework"
        ),
        .binaryTarget(
            name: "libmarisa",
            path: "../../Frameworks/libmarisa.xcframework"
        ),
        .binaryTarget(
            name: "libleveldb",
            path: "../../Frameworks/libleveldb.xcframework"
        ),
        .binaryTarget(
            name: "libopencc",
            path: "../../Frameworks/libopencc.xcframework"
        ),
        .binaryTarget(
            name: "libyaml-cpp",
            path: "../../Frameworks/libyaml-cpp.xcframework"
        ),
        .binaryTarget(
            name: "libglog",
            path: "../../Frameworks/libglog.xcframework"
        ),
        .binaryTarget(
            name: "boost_filesystem",
            path: "../../Frameworks/boost_filesystem.xcframework"
        ),
        .binaryTarget(
            name: "boost_regex",
            path: "../../Frameworks/boost_regex.xcframework"
        ),
        .binaryTarget(
            name: "boost_atomic",
            path: "../../Frameworks/boost_atomic.xcframework"
        ),
        .target(
            name: "RimeEngineC",
            dependencies: [
                "librime",
                "libmarisa",
                "libleveldb",
                "libopencc",
                "libyaml-cpp",
                "libglog",
                "boost_filesystem",
                "boost_regex",
                "boost_atomic",
            ],
            path: "Sources/RimeEngineC",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
        .target(
            name: "RimeEngine",
            dependencies: [
                "RimeEngineC",
                .product(name: "KeyboardModels", package: "KeyboardModels"),
            ],
            path: "Sources/RimeEngine"
        ),
    ]
)

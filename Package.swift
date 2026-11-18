// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "pplz",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "PplzCore", targets: ["PplzCore"]),
        .executable(name: "pplz", targets: ["pplz"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "PplzCore"),
        .executableTarget(
            name: "pplz",
            dependencies: [
                "PplzCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "PplzCoreTests", dependencies: ["PplzCore"]),
    ]
)

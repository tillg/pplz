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
        // SwiftUI views shared by the Mac app now and the iOS / iPadOS app later.
        .target(name: "PplzUI", dependencies: ["PplzCore"]),
        // The Mac app; `scripts/make-app.sh` wraps it into pplz.app.
        .executableTarget(name: "PplzApp", dependencies: ["PplzUI"]),
        .testTarget(name: "PplzCoreTests", dependencies: ["PplzCore"]),
    ]
)

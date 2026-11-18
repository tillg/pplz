// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "pplz",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "PplzCore", targets: ["PplzCore"]),
        .library(name: "PplzUI", targets: ["PplzUI"]),
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
        // SwiftUI views shared by the Mac and the iOS / iPadOS app (Xcode project in App/).
        .target(name: "PplzUI", dependencies: ["PplzCore"]),
        .testTarget(name: "PplzCoreTests", dependencies: ["PplzCore"]),
        .testTarget(name: "PplzUITests", dependencies: ["PplzUI"]),
    ]
)

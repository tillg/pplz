// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "cardxchange",
    // the apps speak English, German and French (issue #13); English is the fallback
    defaultLocalization: "en",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "CXCore", targets: ["CXCore"]),
        .library(name: "CXUI", targets: ["CXUI"]),
        .executable(name: "cx", targets: ["cx"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "CXCore"),
        .executableTarget(
            name: "cx",
            dependencies: [
                "CXCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // SwiftUI views shared by the Mac and the iOS / iPadOS app (Xcode project in App/).
        .target(name: "CXUI", dependencies: ["CXCore"], resources: [.process("Localizable.xcstrings"), .copy("Resources/whats-new.json")]),
        .testTarget(name: "CXCoreTests", dependencies: ["CXCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "CXUITests", dependencies: ["CXUI"]),
    ]
)

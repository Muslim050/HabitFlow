// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HabitCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "HabitCore", targets: ["HabitCore"])
    ],
    targets: [
        .target(
            name: "HabitCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HabitCoreTests",
            dependencies: ["HabitCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

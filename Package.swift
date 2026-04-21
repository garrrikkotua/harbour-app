// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Harbour",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HarbourCore", targets: ["HarbourCore"]),
    ],
    targets: [
        // Pure-logic library shared between GUI, daemon, and tests.
        .target(
            name: "HarbourCore",
            path: "Sources/HarbourCore"
        ),
        .executableTarget(
            name: "Harbour",
            dependencies: ["HarbourCore"],
            path: "Sources/Harbour"
        ),
        .executableTarget(
            name: "harbour-daemon",
            dependencies: ["HarbourCore"],
            path: "Sources/HarbourDaemon"
        ),
        .testTarget(
            name: "HarbourCoreTests",
            dependencies: ["HarbourCore"],
            path: "Tests/HarbourCoreTests"
        ),
    ]
)

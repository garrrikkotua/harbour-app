// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Harbour",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HarbourCore", targets: ["HarbourCore"]),
    ],
    dependencies: [
        // In-app updates (EdDSA-signed appcast). Pinned to a minor line so a
        // release never picks up an untested Sparkle by accident.
        .package(url: "https://github.com/sparkle-project/Sparkle", .upToNextMinor(from: "2.9.6")),
    ],
    targets: [
        // Pure-logic library shared between GUI, daemon, and tests.
        .target(
            name: "HarbourCore",
            path: "Sources/HarbourCore"
        ),
        .executableTarget(
            name: "Harbour",
            dependencies: [
                "HarbourCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
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

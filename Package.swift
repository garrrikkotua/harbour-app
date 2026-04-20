// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Harbour",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Harbour",
            path: "Sources/Harbour"
        ),
        .executableTarget(
            name: "harbour-daemon",
            path: "Sources/HarbourDaemon"
        ),
    ]
)

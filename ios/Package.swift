// swift-tools-version: 6.0
// Lets the sound engine in Swellotic/Core be tested on its own with `swift test`, without a simulator.
// The app itself is built from Swellotic.xcodeproj, which compiles the same files.
import PackageDescription

let package = Package(
    name: "SwellCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    targets: [
        .target(name: "SwellCore", path: "Swellotic/Core", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SwellCoreTests", dependencies: ["SwellCore"], path: "Tests/SwellCoreTests",
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

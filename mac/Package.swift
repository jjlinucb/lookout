// swift-tools-version:5.10
// Lookout for Mac: an on-device accountability app. Build with mac/build_app.sh.
import PackageDescription

let package = Package(
    name: "Lookout",
    platforms: [.macOS("14.0")],
    targets: [
        // The rules, with no AppKit, so they can be tested on their own.
        .target(name: "LookoutCore", path: "Sources/LookoutCore"),
        .executableTarget(name: "Lookout", dependencies: ["LookoutCore"], path: "Sources/Lookout"),
        .testTarget(name: "LookoutCoreTests", dependencies: ["LookoutCore"], path: "Tests/LookoutCoreTests"),
    ],
    swiftLanguageVersions: [.v5]
)

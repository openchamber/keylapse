// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keylapse",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Keylapse", targets: ["Keylapse"])],
    targets: [
        .target(name: "KeylapseCore"),
        .executableTarget(name: "Keylapse", dependencies: ["KeylapseCore"]),
        .testTarget(name: "KeylapseCoreTests", dependencies: ["KeylapseCore"])
    ],
    swiftLanguageModes: [.v5]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keylapse",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Keylapse", targets: ["Keylapse"])],
    dependencies: [
        // In-app updates from the GitHub releases (see scripts/build.sh for how it is bundled).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(name: "KeylapseCore"),
        .executableTarget(name: "Keylapse", dependencies: ["KeylapseCore", .product(name: "Sparkle", package: "Sparkle")],
                          // The framework is copied into Keylapse.app/Contents/Frameworks by scripts/build.sh.
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "KeylapseCoreTests", dependencies: ["KeylapseCore"])
    ],
    swiftLanguageModes: [.v5]
)

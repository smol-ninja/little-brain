// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LittleBrain",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "LittleBrain", targets: ["LittleBrain"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .executableTarget(name: "LittleBrain", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.linkedLibrary("sqlite3"),
                                           .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "LittleBrainTests", dependencies: ["LittleBrain"])
    ],
    swiftLanguageModes: [.v5]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LittleBrain",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "LittleBrain", targets: ["LittleBrain"])],
    targets: [
        .executableTarget(name: "LittleBrain", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "LittleBrainTests", dependencies: ["LittleBrain"])
    ],
    swiftLanguageModes: [.v5]
)

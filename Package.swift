// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexPulse",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "CodexPulse", targets: ["CodexPulse"])],
    targets: [
        .executableTarget(name: "CodexPulse", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "CodexPulseTests", dependencies: ["CodexPulse"])
    ],
    swiftLanguageModes: [.v5]
)

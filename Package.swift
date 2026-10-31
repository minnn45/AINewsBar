// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AINewsBar",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "AINewsBar", path: "Sources/AINewsBar")
    ],
    swiftLanguageModes: [.v5]
)

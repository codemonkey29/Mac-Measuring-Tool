// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeasuringTool",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MeasuringTool"),
        .testTarget(name: "MeasuringToolTests", dependencies: ["MeasuringTool"]),
    ],
    swiftLanguageModes: [.v5]
)

// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DueBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DueKit", path: "Sources/DueKit"),
        .executableTarget(name: "DueBar", dependencies: ["DueKit"], path: "Sources/DueBar"),
        .testTarget(name: "DueKitTests", dependencies: ["DueKit"], path: "Tests/DueKitTests"),
    ]
)

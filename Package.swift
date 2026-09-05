// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Zest",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Zest",
            path: "Sources/Zest"
        ),
        // Unit tests over the pure logic (config decoding, panel gating, battery math,
        // health projection). `swift test` from the repo root; CI runs the same.
        .testTarget(
            name: "ZestTests",
            dependencies: ["Zest"],
            path: "Tests/ZestTests"
        )
    ]
)

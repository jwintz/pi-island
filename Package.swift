// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PiIsland",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PiIsland", targets: ["PiIsland"])
    ],
    targets: [
        .executableTarget(
            name: "PiIsland",
            path: "Sources/PiIsland",
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)

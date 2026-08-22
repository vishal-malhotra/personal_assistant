// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PersonalAssistant",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "PersonalAssistant",
            targets: ["PersonalAssistant"]
        ),
    ],
    dependencies: [
        // Pluggable dependencies for on-device inference:
        // .package(url: "https://github.com/ggerganov/llama.cpp", branch: "master"),
        // .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "PersonalAssistant",
            path: "Sources"
        ),
        .testTarget(
            name: "PersonalAssistantTests",
            dependencies: ["PersonalAssistant"],
            path: "Tests"
        )
    ]
)

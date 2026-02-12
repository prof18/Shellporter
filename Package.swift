// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Shellporter",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Shellporter", targets: ["Shellporter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
    ],
    targets: [
        .executableTarget(
            name: "Shellporter",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Shellporter",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "ShellporterTests",
            dependencies: ["Shellporter"],
            path: "Tests/ShellporterTests"
        ),
    ]
)

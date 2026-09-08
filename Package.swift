// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Aura",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "AuraCore", targets: ["AuraCore"]),
        .executable(name: "Aura", targets: ["Aura"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .target(name: "AuraCore", path: "Sources/AuraCore"),
        .executableTarget(
            name: "Aura",
            dependencies: ["AuraCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Aura",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AuraCoreTests",
            dependencies: ["AuraCore"],
            path: "Tests/AuraCoreTests"
        ),
        .testTarget(
            name: "AuraTests",
            dependencies: ["Aura", "AuraCore"],
            path: "Tests/AuraTests",
            linkerSettings: [
                // SwiftPM does not add its binary-framework output directory to
                // test bundles that depend on an executable target.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../.."])
            ]
        ),
    ]
)

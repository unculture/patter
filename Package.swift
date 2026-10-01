// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Wisp",
    platforms: [.macOS(.v14)],
    dependencies: [
        // traits: [] drops the text-normalization engine, which Wisp does not use.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.4", traits: []),
    ],
    targets: [
        .executableTarget(
            name: "Wisp",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/Wisp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

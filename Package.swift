// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Patter",
    platforms: [.macOS(.v14)],
    dependencies: [
        // traits: [] drops the text-normalization engine, which Patter does not use.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.4", traits: []),
    ],
    targets: [
        .executableTarget(
            name: "Patter",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/Patter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

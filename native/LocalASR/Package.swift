// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "LocalASR", platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.4"),
        .package(path: ".vendor/SpeechKernels"),
        .package(path: ".vendor/FluidAudio", traits: [])
    ], targets: [
        .executableTarget(name: "SaytileModelWorker", dependencies: [
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "Qwen3ASR", package: "SpeechKernels"),
            .product(name: "NemotronStreamingASR", package: "SpeechKernels"),
            .product(name: "FluidAudio", package: "FluidAudio")
        ])
    ], swiftLanguageModes: [.v5])

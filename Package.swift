// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Saytile",
    platforms: [.macOS("26.0")],
    products: [.library(name: "SaytileVoiceUI", type: .static, targets: ["SaytileVoiceUI"]), .library(name: "SaytileKit", type: .static, targets: ["SaytileKit"]), .executable(name: "Saytile", targets: ["SaytileApp"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "CAudio", exclude: ["WEBRTC-LICENSE.txt", "webrtc/common_audio/signal_processing/dot_product_with_scale.cc"], cSettings: [.headerSearchPath("."), .define("WEBRTC_POSIX")]),
        .target(name: "SaytileKit", dependencies: ["CSQLite", "CAudio"], resources: [.copy("Resources/ConnectionSample.pcm"), .copy("Resources/LocalASR")]),
        .target(name: "SaytileVoiceUI"),
        .executableTarget(name: "SaytileApp", dependencies: ["SaytileKit", "SaytileVoiceUI"], resources: [.copy("Resources/SaytileBrandMark.png")]),
        .testTarget(name: "SaytileKitTests", dependencies: ["SaytileKit", "SaytileVoiceUI"], path: "tests/SaytileKitTests")
    ]
)

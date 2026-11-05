// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Saytile",
    platforms: [.macOS("26.0")],
    products: [.library(name: "SaytileKit", targets: ["SaytileKit"]), .executable(name: "Saytile", targets: ["SaytileApp"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "CAudio", exclude: ["WEBRTC-LICENSE.txt", "webrtc/common_audio/signal_processing/dot_product_with_scale.cc"], cSettings: [.headerSearchPath("."), .define("WEBRTC_POSIX")]),
        .target(name: "SaytileKit", dependencies: ["CSQLite", "CAudio"]),
        .executableTarget(name: "SaytileApp", dependencies: ["SaytileKit"]),
        .testTarget(name: "SaytileKitTests", dependencies: ["SaytileKit"], path: "tests/SaytileKitTests")
    ]
)

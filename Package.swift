// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Saytile",
    platforms: [.macOS("26.0")],
    products: [.library(name: "SaytileKit", targets: ["SaytileKit"]), .executable(name: "Saytile", targets: ["SaytileApp"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "CAudio", exclude: ["WEBRTC-LICENSE.txt"], cSettings: [.headerSearchPath("."), .define("WEBRTC_POSIX")]),
        .target(name: "SaytileKit", dependencies: ["CSQLite", "CAudio"]),
        .executableTarget(name: "SaytileApp", dependencies: ["SaytileKit"]),
        .testTarget(name: "SaytileKitTests", dependencies: ["SaytileKit"])
    ]
)

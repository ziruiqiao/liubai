// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiuBai",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LiuBai", targets: ["LiuBai"]),
        .executable(name: "LiuBaiChecks", targets: ["LiuBaiChecks"])
    ],
    targets: [
        .target(name: "LiuBaiCore"),
        .target(name: "LiuBaiAudio", dependencies: ["LiuBaiCore"]),
        .executableTarget(name: "LiuBai", dependencies: ["LiuBaiCore", "LiuBaiAudio"]),
        .executableTarget(name: "LiuBaiChecks", dependencies: ["LiuBaiCore", "LiuBaiAudio"])
    ],
    swiftLanguageModes: [.v5]
)

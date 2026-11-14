// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DamaCraft",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DamaCraft", targets: ["DamaCraft"])],
    targets: [.executableTarget(name: "DamaCraft", path: "Sources/DamaCraft")]
)

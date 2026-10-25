// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Curios",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Curios", targets: ["Curios"]), .library(name: "CuriosCore", targets: ["CuriosCore"])],
    targets: [
        .target(name: "CuriosCore"),
        .executableTarget(name: "Curios", dependencies: ["CuriosCore"]),
        .testTarget(name: "CuriosCoreTests", dependencies: ["CuriosCore"])
    ],
    swiftLanguageModes: [.v5]
)

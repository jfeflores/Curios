// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Curios",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Curios", targets: ["Daybook"]), .library(name: "DaybookCore", targets: ["DaybookCore"])],
    targets: [
        .target(name: "DaybookCore"),
        .executableTarget(name: "Daybook", dependencies: ["DaybookCore"]),
        .testTarget(name: "DaybookCoreTests", dependencies: ["DaybookCore"])
    ],
    swiftLanguageModes: [.v5]
)

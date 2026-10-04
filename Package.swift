// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RescueCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "RescueCore", targets: ["RescueCore"])],
    targets: [
        .target(name: "RescueCore"),
        .testTarget(
            name: "RescueCoreTests", dependencies: ["RescueCore"], path: "Tests/RescueCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)

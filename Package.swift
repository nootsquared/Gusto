// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GustoCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "GustoCore", targets: ["GustoCore"])],
    targets: [
        .target(name: "GustoCore"),
        .testTarget(
            name: "GustoCoreTests", dependencies: ["GustoCore"], path: "Tests/GustoCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)

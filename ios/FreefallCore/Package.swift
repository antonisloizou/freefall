// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreefallCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "FreefallCore", targets: ["FreefallCore"])],
    targets: [
        .target(name: "CGPMF", publicHeadersPath: "include"),
        .target(name: "FreefallCore", dependencies: ["CGPMF"]),
        .executableTarget(name: "FreefallCoreChecks", dependencies: ["FreefallCore"], path: "Checks")
    ]
)

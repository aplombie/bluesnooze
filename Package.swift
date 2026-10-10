// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProcaineCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "ProcaineCore", targets: ["ProcaineCore"])],
    targets: [
        .target(name: "ProcaineCore", path: "Procaine/Core"),
        .testTarget(name: "ProcaineCoreTests", dependencies: ["ProcaineCore"])
    ]
)

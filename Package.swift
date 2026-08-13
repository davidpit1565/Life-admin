// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LifeAdmin",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LifeAdminCore", targets: ["LifeAdminCore"]),
        .executable(name: "lifeadmin-qa", targets: ["LifeAdminQA"])
    ],
    targets: [
        .target(name: "LifeAdminCore", resources: [.process("Resources")]),
        .executableTarget(name: "LifeAdminQA", dependencies: ["LifeAdminCore"]),
        .testTarget(name: "LifeAdminCoreTests", dependencies: ["LifeAdminCore"])
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AITide",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tide", targets: ["Tide"]), .executable(name: "tide-probe", targets: ["TideProbe"]), .executable(name: "tide-tests", targets: ["TideTests"])],
    targets: [
        .target(name: "TideCore", linkerSettings: [.linkedFramework("Security")]),
        .executableTarget(name: "Tide", dependencies: ["TideCore"], resources: [.process("Resources")]),
        .executableTarget(name: "TideProbe", dependencies: ["TideCore"]),
        .executableTarget(name: "TideTests", dependencies: ["TideCore"], path: "Tests/TideCoreTests")
    ],
    swiftLanguageModes: [.v5]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TapThatMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TapThatMac", targets: ["TapThatMac"]),
        .executable(name: "TapSensorHelper", targets: ["TapSensorHelper"]),
        .executable(name: "SensorProbe", targets: ["SensorProbe"]),
        .executable(name: "ReplayCaptures", targets: ["ReplayCaptures"])
    ],
    targets: [
        .target(name: "TapCore"),
        .executableTarget(name: "TapThatMac", dependencies: ["TapCore"]),
        .executableTarget(name: "TapSensorHelper", dependencies: ["TapCore"]),
        .executableTarget(name: "SensorProbe", dependencies: ["TapCore"]),
        .executableTarget(name: "ReplayCaptures", dependencies: ["TapCore"]),
        .testTarget(name: "TapThatMacTests", dependencies: ["TapThatMac", "TapCore"]),
        .testTarget(
            name: "TapCoreTests",
            dependencies: ["TapCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)

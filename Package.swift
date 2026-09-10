// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TapThatX",
    platforms: [.macOS(.v14)],
    products: [
    ],
    targets: [
        .target(name: "TapCore"),
        .testTarget(name: "TapCoreTests", dependencies: ["TapCore"], resources: [.copy("Fixtures/calibration-labeled.json"), .copy("Fixtures/verification-round1.json")])
    ],
    swiftLanguageModes: [.v5]
)

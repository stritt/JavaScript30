// swift-tools-version:5.9
import PackageDescription

// Pure game logic for Stepquest. No UIKit / SpriteKit / HealthKit imports so it
// builds and tests on Linux as well as Apple platforms.
let package = Package(
    name: "StepquestKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "StepquestKit", targets: ["StepquestKit"]),
    ],
    targets: [
        .target(
            name: "StepquestKit",
            resources: [
                // Bundled copy of shared/formulas.json (kept in sync by
                // FormulasTests.testBundledCopyMatchesSharedSourceOfTruth).
                .copy("Resources/formulas.json"),
            ]
        ),
        .testTarget(
            name: "StepquestKitTests",
            dependencies: ["StepquestKit"]
        ),
    ]
)

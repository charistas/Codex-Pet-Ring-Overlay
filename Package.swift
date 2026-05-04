// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexPetRingOverlay",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "codex-pet-ring-overlay", targets: ["CodexPetRingOverlay"]),
    ],
    targets: [
        .target(name: "CodexPetRingOverlayCore"),
        .executableTarget(
            name: "CodexPetRingOverlay",
            dependencies: ["CodexPetRingOverlayCore"]
        ),
        .testTarget(
            name: "CodexPetRingOverlayCoreTests",
            dependencies: ["CodexPetRingOverlayCore"]
        ),
    ]
)

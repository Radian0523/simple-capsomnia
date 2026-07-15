// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Capsomnia",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Capsomnia", targets: ["Capsomnia"]),
        .executable(name: "CapsomniaAgentReporter", targets: ["CapsomniaAgentReporter"]),
        .executable(
            name: "com.github.oonishidaichi.capsomnia.pmset-helper",
            targets: ["CapsomniaPmsetHelper"]
        )
    ],
    targets: [
        .target(name: "CapsomniaAgentCore"),
        .target(name: "CapsomniaPmsetHelperCore"),
        .target(
            name: "CapsomniaCore",
            dependencies: ["CapsomniaPmsetHelperCore"]
        ),
        .executableTarget(
            name: "Capsomnia",
            dependencies: [
                "CapsomniaAgentCore",
                "CapsomniaCore",
                "CapsomniaPmsetHelperCore"
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "CapsomniaAgentReporter",
            dependencies: ["CapsomniaAgentCore"]
        ),
        .executableTarget(
            name: "CapsomniaPmsetHelper",
            dependencies: ["CapsomniaPmsetHelperCore"]
        ),
        .testTarget(
            name: "CapsomniaCoreTests",
            dependencies: ["CapsomniaCore", "CapsomniaPmsetHelperCore"]
        ),
        .testTarget(
            name: "CapsomniaPmsetHelperTests",
            dependencies: ["CapsomniaPmsetHelperCore"]
        ),
        .testTarget(
            name: "CapsomniaIntegrationTests",
            dependencies: ["CapsomniaCore", "CapsomniaPmsetHelperCore"]
        ),
        .testTarget(
            name: "CapsomniaAppTests",
            dependencies: ["Capsomnia"]
        ),
        .testTarget(
            name: "CapsomniaAgentCoreTests",
            dependencies: ["CapsomniaAgentCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)

// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MonitorKeyboardFix",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "IOAVServiceBridge",
            path: "Sources/IOAVServiceBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(
            name: "MonitorKeyboardFix",
            dependencies: ["IOAVServiceBridge"],
            path: "Sources/MonitorKeyboardFix",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreDisplay")
            ]
        )
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AXProbe",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AXProbe",
            path: "Sources/AXProbe",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)

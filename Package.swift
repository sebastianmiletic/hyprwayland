// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Waycode",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Waycode", targets: ["Waycode"])],
    targets: [
        .executableTarget(
            name: "Waycode",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreWLAN")
            ]
        )
    ]
)

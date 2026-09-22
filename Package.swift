// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hyprshell",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Hyprshell", targets: ["Hyprshell"])],
    targets: [
        .executableTarget(
            name: "Hyprshell",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreWLAN")
            ]
        )
    ]
)

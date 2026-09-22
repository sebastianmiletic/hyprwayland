// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ryft",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Ryft", targets: ["Ryft"])],
    targets: [
        .executableTarget(
            name: "Ryft",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreWLAN")
            ]
        )
    ]
)

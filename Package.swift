// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Curstyle",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CursorKit", targets: ["CursorKit"]),
        .executable(name: "curstyle", targets: ["curstyle"]),
    ],
    targets: [
        .target(
            name: "CCursorBridge",
            linkerSettings: [.linkedFramework("ApplicationServices")]
        ),
        .target(
            name: "CursorKit",
            dependencies: ["CCursorBridge"]
        ),
        .executableTarget(
            name: "curstyle",
            dependencies: ["CursorKit"]
        ),
        .executableTarget(
            name: "curstyle-probe",
            dependencies: ["CCursorBridge"]
        ),
    ]
)

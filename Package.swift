// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Curstyle",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CursorKit", targets: ["CursorKit"]),
        .executable(name: "curstyle", targets: ["curstyle"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.10.0")
    ],
    targets: [
        .target(
            name: "CCursorBridge",
            linkerSettings: [.linkedFramework("ApplicationServices")]
        ),
        .target(
            name: "CursorKit",
            dependencies: ["CCursorBridge"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "curstyle",
            dependencies: ["CursorKit"]
        ),
        // .app の本体。make-app.sh が curstyle(ヘルパーを兼ねる)と一緒にバンドルへ詰める。
        // 名前を Curstyle にしないのは、大文字小文字を区別しないファイルシステムで curstyle と衝突するため。
        .executableTarget(
            name: "CurstyleApp",
            dependencies: [
                "CursorKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .executableTarget(
            name: "curstyle-probe",
            dependencies: ["CCursorBridge"]
        ),
        // 測定用の使い捨てコードなので、厳密な並行性チェックは外す。
        .executableTarget(
            name: "curstyle-overlay-probe",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CursorKitTests",
            dependencies: ["CursorKit"]
        ),
    ]
)

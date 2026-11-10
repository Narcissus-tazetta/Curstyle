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
        // .app の本体。make-app.sh が curstyle(ヘルパーを兼ねる)と一緒にバンドルへ詰める。
        // 名前を Curstyle にしないのは、大文字小文字を区別しないファイルシステムで curstyle と衝突するため。
        .executableTarget(
            name: "CurstyleApp",
            dependencies: ["CursorKit"],
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
    ]
)

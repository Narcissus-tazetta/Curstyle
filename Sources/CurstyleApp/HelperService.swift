import CursorKit
import Foundation
import ServiceManagement

/// 自動再適用ヘルパーの登録。バンドルの Contents/Library/LaunchAgents にある plist を SMAppService で登録し、
/// 実体はバンドル内の curstyle(`helper run`)。
/// ラベルは `curstyle helper install`(~/Library/LaunchAgents に置く旧方式)と同じにしてある。
/// 両方が動くと再適用が二重になるので、こちらを有効にするときは旧方式を先に外す。
enum HelperService {
    static let label = "io.github.narcissus-tazetta.curstyle.helper"
    static var service: SMAppService { .agent(plistName: "\(label).plist") }

    enum State: Equatable {
        case enabled
        case requiresApproval
        case disabled
        /// .app として起動していない(swift run など)か、バンドルに plist が無い。
        case unavailable
    }

    static var state: State {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .disabled
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    static var legacyPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var hasLegacyInstall: Bool { FileManager.default.fileExists(atPath: legacyPlist.path) }

    static func enable() throws {
        if hasLegacyInstall {
            // 動いていない(bootout 済み)なら失敗するが、plist を消せば足りるので終了コードは見ない。
            _ = try launchctl(["bootout", "gui/\(getuid())/\(label)"])
            try FileManager.default.removeItem(at: legacyPlist)
        }
        try service.register()
    }

    static func disable() throws {
        try service.unregister()
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}

/// メニューバーに常駐させるためのログイン項目(アプリ本体)。
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

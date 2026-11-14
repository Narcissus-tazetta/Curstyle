import AppKit
import Observation
import Sparkle

/// Sparkle の薄い包み。Info.plist に SUFeedURL と SUPublicEDKey があるビルド(scripts/package.sh)でだけ有効になる。
/// make-app.sh で組み立てたローカルビルドが、自分を公開版で上書きしに行かないようにするため。
@MainActor
@Observable
final class UpdateService {
    let isAvailable: Bool
    private(set) var automaticallyChecks: Bool

    @ObservationIgnored private let controller: SPUStandardUpdaterController?

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        isAvailable = info["SUFeedURL"] != nil && info["SUPublicEDKey"] != nil
        controller =
            isAvailable
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
        automaticallyChecks = controller?.updater.automaticallyChecksForUpdates ?? false
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecks = enabled
    }

    func checkForUpdates() {
        // メニューバー常駐(.accessory)のままだと、確認ダイアログが他のアプリの後ろに出る。
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}

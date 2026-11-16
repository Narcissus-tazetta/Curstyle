import CursorKit
import Foundation
import Observation

/// 試用画面で確かめる役割。登録先(resolvedPlan の名前)で判定するので、別名や cursor.13 も同じ役割になる。
enum TryoutRole: CaseIterable, Hashable {
    case arrow, ibeam, pointingHand
    /// マップのドラッグ移動で使う。サンプルにマップを足したときだけ確かめる。
    case openHand, closedHand

    static let basic: [TryoutRole] = [.arrow, .ibeam, .pointingHand]

    var title: String {
        switch self {
        case .arrow: L10n.text("矢印")
        case .ibeam: L10n.text("テキスト")
        case .pointingHand: L10n.text("リンク")
        case .openHand: L10n.text("手(開)")
        case .closedHand: L10n.text("手(掴む)")
        }
    }

    fileprivate var key: String {
        switch self {
        case .arrow: "arrow"
        case .ibeam: "ibeam"
        case .pointingHand: "pointingHand"
        case .openHand: "openHand"
        case .closedHand: "closedHand"
        }
    }

    /// 適用エンジンが実際に登録する名前。
    fileprivate var registeredName: String {
        // 固定のキーは CursorCatalog が必ず解決する(openHand / closedHand は roleNames 経由で cursor.12 / 11)。
        try! CursorCatalog.targets(for: key)[0]
    }
}

/// 基準テーマに共通の倍率をかけた結果を持つ。プレビューと保存は同じ `result` を使う。
/// 倍率は毎回基準テーマからかけ直す(縮小した画像を再拡大して劣化させない)。
@MainActor
@Observable
final class TryoutSession {
    let base: CursorTheme
    /// 倍率の上限。最大のカーソルが 256 pt を超えない範囲に限る。
    let maxFactor: Double

    private(set) var factor = 1.0
    private(set) var result: CursorTheme
    private(set) var resultFactor = 1.0
    private(set) var isScaling = false
    private(set) var error: String?
    /// 試用エリアに出すカーソル。スライダーを動かしている間も追従させるため、この3つだけは倍率を即座にかけ直す
    /// (保存する全体は少し遅れて作る。同じ `scalingSize` なので、できあがりは保存データと一致する)。
    private(set) var reps: [TryoutRole: CursorRep] = [:]

    private let baseReps: [TryoutRole: CursorRep]
    private var task: Task<Void, Never>?

    init(base: CursorTheme) {
        self.base = base
        result = base
        let largest = base.cursors.values.map { max($0.size.width, $0.size.height) }.max() ?? 1
        maxFactor = min(5, (256 / largest * 10).rounded(.down) / 10)
        do {
            baseReps = try Self.roleReps(base)
        } catch {
            baseReps = [:]
            self.error = "\(error)"
        }
        reps = baseReps
    }

    /// 画面に出ている倍率が、保存できる状態の結果と一致している。
    var isCurrent: Bool { !isScaling && error == nil && resultFactor == factor }

    var isModified: Bool { resultFactor != 1 }

    func setFactor(_ value: Double) {
        let snapped = min(max((value * 10).rounded() / 10, 0.1), maxFactor)
        guard snapped != factor else { return }
        factor = snapped
        task?.cancel()
        if snapped == 1 {
            result = base
            resultFactor = 1
            isScaling = false
            reps = baseReps
            error = nil
            return
        }
        isScaling = true
        error = nil
        do {
            reps = try baseReps.mapValues { try $0.scalingSize(by: snapped) }
        } catch {
            self.error = "\(error)"
        }
        let base = base
        task = Task { [weak self] in
            // スライダーを動かしている間は変換せず、止まってから1回だけ作る。
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try base.scalingSize(by: snapped) }
            }.value
            guard !Task.isCancelled, let self, self.factor == snapped else { return }
            self.finish(outcome, factor: snapped)
        }
    }

    func reset() { setFactor(1) }

    private func finish(_ outcome: Result<CursorTheme, Error>, factor: Double) {
        isScaling = false
        do {
            let scaled = try outcome.get()
            _ = try scaled.resolvedPlan()
            reps = try Self.roleReps(scaled)
            result = scaled
            resultFactor = factor
        } catch {
            self.error = "\(error)"
        }
    }

    private static func roleReps(_ theme: CursorTheme) throws -> [TryoutRole: CursorRep] {
        let plan = try theme.resolvedPlan()
        return Dictionary(
            uniqueKeysWithValues: TryoutRole.allCases.compactMap { role in
                plan.first { $0.name == role.registeredName }.map { (role, $0.rep) }
            })
    }
}

import CursorKit
import SwiftUI

/// 試用エリア・サイズ調整・足りない役割の表示。取り込み画面と追加済みテーマのシートで共通。
struct ThemeTryoutView: View {
    let session: TryoutSession
    var note: String?

    @State private var sampleAppearance = SampleAppearance.automatic
    @Environment(\.colorScheme) private var colorScheme

    private enum SampleAppearance { case automatic, light, dark }

    private var darkSample: Bool {
        switch sampleAppearance {
        case .automatic: colorScheme == .dark
        case .light: false
        case .dark: true
        }
    }
    /// 試用は 1 pt = 画面の 1 pt で描く。システムのポインターサイズが標準でないと、適用後の大きさは一致しない可能性がある。
    private let pointerScale = SystemPointer.sizeScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("試してみる")).font(.headline)
                Spacer()
                Picker(L10n.text("試用の背景"), selection: $sampleAppearance) {
                    Text(L10n.text("自動")).tag(SampleAppearance.automatic)
                    Image(systemName: "sun.max")
                        .accessibilityLabel(L10n.text("明るい"))
                        .help(L10n.text("明るい"))
                        .tag(SampleAppearance.light)
                    Image(systemName: "moon")
                        .accessibilityLabel(L10n.text("暗い"))
                        .help(L10n.text("暗い"))
                        .tag(SampleAppearance.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
                .help(L10n.text("試用の背景(自動はシステムの外観に従います)"))
            }
            TryoutSurface(reps: session.reps, dark: darkSample)
            Text(L10n.text("このエリアで動かして試せます。ここではシステムのカーソルは変更されません。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            sizeControls
            ForEach(TryoutRole.allCases.filter { session.reps[$0] == nil }, id: \.self) { role in
                Label(
                    L10n.text("{0}: テーマに含まれていません。適用時は標準を使います", role.title),
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sizeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(L10n.text("大きさ"))
                Slider(
                    value: Binding(get: { session.factor }, set: { session.setFactor($0) }),
                    in: 0.1...session.maxFactor, step: 0.1
                ) {
                    Text(L10n.text("大きさ"))
                } minimumValueLabel: {
                    Text("0.1×")
                } maximumValueLabel: {
                    Text(String(format: "%.1f×", session.maxFactor))
                }
                .labelsHidden()
                Text(String(format: L10n.text("%.1f 倍"), session.factor))
                    .font(.callout.monospacedDigit().weight(.medium))
                    .frame(width: 56, alignment: .trailing)
                Button(L10n.text("元の大きさに戻す")) { session.reset() }
                    .disabled(session.factor == 1)
            }
            HStack(spacing: 6) {
                Text(sizeSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if session.isScaling {
                    ProgressView().controlSize(.mini)
                    Text(L10n.text("計算しています…")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 16)
            if session.factor > 1 {
                Text(L10n.text("元の画像より大きくすると、輪郭がぼやけます。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if pointerScale > 1.01 {
                Label(
                    L10n.text(
                        "システムのポインターサイズが {0} 倍に設定されています。適用後の実際の大きさは、この試用と違う可能性があります。",
                        String(format: "%.1f", pointerScale)),
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = session.error {
                Label(L10n.text("このサイズでは保存できません: {0}", error), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .cardBackground()
    }

    /// 矢印があれば実際の幅×高さ、なければテーマ全体の範囲。
    private var sizeSummary: String {
        if let arrow = session.reps[.arrow] {
            return L10n.text(
                "矢印: {0}×{1} pt", String(Int(arrow.size.width)), String(Int(arrow.size.height)))
        }
        let sides = session.result.cursors.values.map { Int(max($0.size.width, $0.size.height)) }
        guard let low = sides.min(), let high = sides.max() else { return "-" }
        return low == high
            ? "\(low) pt" : L10n.text("{0}〜{1} pt", String(low), String(high))
    }
}

/// 追加済みのテーマを試して、大きさを整えて保存する。保存だけではシステムに適用しない。
struct ThemeTryoutSheet: View {
    let model: AppModel
    let entry: ThemeLibrary.Entry

    @Environment(\.dismiss) private var dismiss
    @State private var session: TryoutSession
    @State private var saveError: String?

    init(model: AppModel, entry: ThemeLibrary.Entry) {
        self.model = model
        self.entry = entry
        _session = State(initialValue: TryoutSession(base: entry.theme))
    }

    private var canSave: Bool { session.isModified && session.isCurrent }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(systemImage: "wand.and.stars", tint: .purple, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("テーマを試して整える")).font(.title3.weight(.semibold))
                    Text(entry.theme.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(20)
            Divider()
            ScrollView {
                ThemeTryoutView(session: session)
                    .padding(20)
            }
            Divider()
            HStack {
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .textSelection(.enabled)
                } else if model.isActive(entry) {
                    Text(L10n.text("適用中のテーマです。保存してもカーソルはすぐには変わらず、「変更を適用」で反映します。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button(L10n.text("キャンセル"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text("保存")) {
                    do {
                        try model.save(entry, with: session.result)
                        dismiss()
                    } catch {
                        saveError = "\(error)"
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(20)
        }
        .frame(width: 640, height: 560)
    }
}

enum SystemPointer {
    /// 「システム設定 > アクセシビリティ > ポインタ」の大きさ(標準 1)。
    static var sizeScale: Double {
        let value = CFPreferencesCopyAppValue(
            "mouseDriverCursorSize" as CFString, "com.apple.universalaccess" as CFString)
        return (value as? NSNumber)?.doubleValue ?? 1
    }
}

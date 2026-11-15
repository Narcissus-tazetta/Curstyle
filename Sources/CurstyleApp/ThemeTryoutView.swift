import AppKit
import CursorKit
import Observation
import SwiftUI

enum SampleAppearance { case automatic, light, dark }

/// 試用エリア・サイズ調整・足りない役割の表示。取り込み画面と比較シートの各エリアで共通。
/// 足したテキスト/ボタンはこの View が持つので、エリアのテーマを入れ替えても残る。
struct ThemeTryoutView: View {
    let session: TryoutSession
    var note: String?
    /// nil なら背景の切り替えを自前で持つ。比較シートは全エリア共通の1つを渡す。
    var appearance: Binding<SampleAppearance>?
    var compact = false

    @State private var ownAppearance = SampleAppearance.automatic
    @State private var extras: [SampleItem] = []
    @State private var draftKind = SampleItem.Kind.text
    @State private var draftLabel = ""
    @Environment(\.colorScheme) private var colorScheme

    private var sampleAppearance: Binding<SampleAppearance> { appearance ?? $ownAppearance }

    private var darkSample: Bool {
        switch sampleAppearance.wrappedValue {
        case .automatic: colorScheme == .dark
        case .light: false
        case .dark: true
        }
    }
    /// 試用は 1 pt = 画面の 1 pt で描く。システムのポインターサイズが標準でないと、適用後の大きさは一致しない可能性がある。
    private let pointerScale = SystemPointer.sizeScale

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            if appearance == nil {
                HStack {
                    Text(L10n.text("試してみる")).font(.headline)
                    Spacer()
                    AppearancePicker(selection: sampleAppearance)
                }
            }
            TryoutSurface(reps: session.reps, dark: darkSample, extras: extras, compact: compact)
            if !compact {
                Text(L10n.text("このエリアで動かして試せます。ここではシステムのカーソルは変更されません。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            extrasEditor
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

    /// サンプルページにテキスト/ボタンを足して、自分の使う場面に近づけて試す。
    private var extrasEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Picker(L10n.text("追加する種類"), selection: $draftKind) {
                    Text(L10n.text("テキスト")).tag(SampleItem.Kind.text)
                    Text(L10n.text("ボタン")).tag(SampleItem.Kind.button)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                TextField(L10n.text("表示する文字"), text: $draftLabel)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addDraft)
                Button(L10n.text("追加"), action: addDraft)
                    .disabled(draftLabel.trimmingCharacters(in: .whitespaces).isEmpty || extras.count >= 8)
            }
            if !extras.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(extras) { item in
                        HStack(spacing: 4) {
                            Image(systemName: item.kind == .text ? "textformat" : "capsule")
                                .imageScale(.small)
                            Text(item.label).lineLimit(1)
                            Button {
                                extras.removeAll { $0.id == item.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.text("削除"))
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
    }

    private func addDraft() {
        let label = draftLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, extras.count < 8 else { return }
        extras.append(SampleItem(kind: draftKind, label: label))
        draftLabel = ""
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

/// 1・左右2・4分割で複数のテーマを並べて比較する。各エリアは別々のテーマ・倍率・追加テキスト/ボタンを持つ。
struct ThemeTryoutSheet: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var panes: [Pane]
    @State private var layout = Split.single
    @State private var appearance = SampleAppearance.automatic
    /// シートは親ウィンドウより大きくできず、はみ出すと端が切れる。開いた時点のウィンドウに収める。
    private let available: CGSize

    enum Split: Int, CaseIterable {
        case single = 1, pair = 2, quad = 4

        var systemImage: String {
            switch self {
            case .single: "rectangle"
            case .pair: "rectangle.split.2x1"
            case .quad: "rectangle.split.2x2"
            }
        }

        var title: String {
            switch self {
            case .single: L10n.text("1つ")
            case .pair: L10n.text("左右に2つ")
            case .quad: L10n.text("4分割")
            }
        }
    }

    /// 1エリア分の状態。テーマを替えると倍率は基準から作り直す(保存していない調整は破棄される)。
    @MainActor
    @Observable
    final class Pane: Identifiable {
        let id = UUID()
        var entry: ThemeLibrary.Entry
        var session: TryoutSession
        var saveError: String?

        init(entry: ThemeLibrary.Entry) {
            self.entry = entry
            session = TryoutSession(base: entry.theme)
        }

        func show(_ entry: ThemeLibrary.Entry) {
            self.entry = entry
            session = TryoutSession(base: entry.theme)
            saveError = nil
        }
    }

    init(model: AppModel, entry: ThemeLibrary.Entry) {
        self.model = model
        available = NSApp.keyWindow?.contentLayoutRect.size ?? CGSize(width: 1000, height: 760)
        // 追加するエリアの初期テーマは、まだ出ていないテーマから順に選ぶ。
        let others = model.entries.filter { $0.id != entry.id }
        let initial = [entry] + others.prefix(3)
        _panes = State(initialValue: (0..<4).map { Pane(entry: initial[$0 % initial.count]) })
    }

    private var visible: ArraySlice<Pane> { panes.prefix(layout.rawValue) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(systemImage: "wand.and.stars", tint: .purple, size: 34)
                Text(L10n.text("テーマを試して整える")).font(.title3.weight(.semibold))
                Spacer()
                Picker(L10n.text("分割"), selection: $layout.animation(Motion.quick)) {
                    ForEach(Split.allCases, id: \.self) { layout in
                        Image(systemName: layout.systemImage)
                            .accessibilityLabel(layout.title)
                            .help(layout.title)
                            .tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
                .help(L10n.text("エリアの分割(1つ・左右に2つ・4分割)"))
                AppearancePicker(selection: $appearance)
            }
            .padding(20)
            Divider()
            ScrollView {
                let columns = Array(
                    repeating: GridItem(.flexible(), spacing: 16, alignment: .top),
                    count: layout == .single ? 1 : 2)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(visible) { pane in
                        PaneView(
                            model: model, pane: pane, appearance: $appearance,
                            compact: layout != .single)
                    }
                }
                .frame(maxWidth: layout == .single ? 640 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            Divider()
            HStack {
                Text(L10n.text("保存しても、カーソルはすぐには変わりません。適用中のテーマは「変更を適用」で反映します。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button(L10n.text("閉じる")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        // 分割を切り替えてもシートの大きさは変わらない(開いた後に広げても、中身がはみ出して切れる)。
        .frame(width: min(1000, available.width - 40), height: min(760, available.height - 40))
    }
}

private struct PaneView: View {
    let model: AppModel
    let pane: ThemeTryoutSheet.Pane
    @Binding var appearance: SampleAppearance
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(model.entries) { candidate in
                        Button {
                            pane.show(candidate)
                        } label: {
                            if candidate.id == pane.entry.id {
                                Label(candidate.theme.name, systemImage: "checkmark")
                            } else {
                                Text(candidate.theme.name)
                            }
                        }
                    }
                } label: {
                    Text(pane.entry.theme.name).lineLimit(1).truncationMode(.middle)
                }
                .fixedSize()
                .help(L10n.text("このエリアで試すテーマ"))
                if model.isActive(pane.entry) {
                    Text(L10n.text("適用中")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(L10n.text("保存")) { save() }
                    .disabled(!(pane.session.isModified && pane.session.isCurrent))
            }
            if let error = pane.saveError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            ThemeTryoutView(session: pane.session, appearance: $appearance, compact: compact)
                .id(pane.id)
        }
        .padding(12)
        .cardBackground()
    }

    private func save() {
        do {
            try model.save(pane.entry, with: pane.session.result)
            // 保存した内容を新しい基準にして、倍率を 1 に戻す(続けて調整・再保存できる)。
            pane.show(model.entry(id: pane.entry.id) ?? pane.entry)
        } catch {
            pane.saveError = "\(error)"
        }
    }
}

/// サンプルページに足すテキスト/ボタン。テキストはテキスト用、ボタンはリンク用のカーソルになる。
struct SampleItem: Identifiable, Equatable {
    enum Kind { case text, button }
    let id = UUID()
    let kind: Kind
    let label: String
}

struct AppearancePicker: View {
    @Binding var selection: SampleAppearance

    var body: some View {
        Picker(L10n.text("試用の背景"), selection: $selection) {
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
}

/// 幅に収まらなければ折り返して並べる。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
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

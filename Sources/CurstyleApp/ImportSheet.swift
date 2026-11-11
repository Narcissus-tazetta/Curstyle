import CursorKit
import SwiftUI

/// 取り込む前に、役割の対応・取り込まないファイル・大きさを見せて確かめてもらう。
struct ImportSheet: View {
    let model: AppModel
    let source: URL

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var pixelsPerPoint = 1
    @State private var result: Result<(theme: CursorTheme, skipped: [String], adjustments: [String]), Error>?

    init(model: AppModel, source: URL) {
        self.model = model
        self.source = source
        _name = State(initialValue: source.deletingPathExtension().lastPathComponent)
    }

    private var isCurstyleTheme: Bool {
        FileManager.default.fileExists(atPath: source.appendingPathComponent("theme.json").path)
    }

    private var isCape: Bool { source.pathExtension.lowercased() == "cape" }

    /// 大きさを選べるのは Windows のフォルダだけ(ほかは pt が決まっている)。
    private var choosesScale: Bool { !isCurstyleTheme && !isCape }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(systemImage: "square.and.arrow.down", tint: .blue, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("テーマを取り込む")).font(.title3.weight(.semibold))
                    Text(source.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Form {
                TextField(L10n.text("名前"), text: $name)
                if choosesScale {
                    Picker(L10n.text("大きさ"), selection: $pixelsPerPoint) {
                        Text(L10n.text("標準(1 px = 1 pt)")).tag(1)
                        Text(L10n.text("小さめ(2 px = 1 pt)")).tag(2)
                    }
                    .pickerStyle(.radioGroup)
                    Text(
                        L10n.text(
                            "Windows の 32 px のカーソルは「標準」で 32 pt になります。「小さめ」は Retina で画素どおりの大きさですが、macOS の標準より小さく見えます。")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: choosesScale ? 150 : 60)

            preview
                .frame(height: 220)

            HStack {
                Spacer()
                Button(L10n.text("キャンセル"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text("ライブラリに追加")) {
                    guard case .success(let parsed)? = result else { return }
                    var theme = parsed.theme
                    theme.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.add(theme)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task(id: pixelsPerPoint) { parse() }
    }

    private var canAdd: Bool {
        guard case .success? = result else { return false }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var preview: some View {
        switch result {
        case .success(let parsed)?:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                        ForEach(parsed.theme.cursors.keys.sorted(by: tileOrder), id: \.self) { key in
                            let rep = parsed.theme.cursors[key]!
                            VStack(spacing: 4) {
                                ZStack {
                                    BackdropView(backdrop: model.backdrop, cornerRadius: 8)
                                    CursorPreview(rep: rep, zoom: min(1.5, 40 / max(rep.size.width, rep.size.height)))
                                }
                                .frame(height: 52)
                                Text(CursorRoles.title(for: key))
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(10)
                    .cardBackground()
                    ForEach(parsed.adjustments, id: \.self) { adjustment in
                        Label(adjustment, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !parsed.skipped.isEmpty {
                        Label(
                            L10n.text(
                                "取り込まないもの: {0}", String(describing: parsed.skipped.sorted().joined(separator: ", "))),
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .failure(let error)?:
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text(isCape ? L10n.text("この .cape は取り込めません") : L10n.text("このフォルダは取り込めません")).font(.headline)
                Text("\(error)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cardBackground()
        case nil:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tileOrder(_ a: String, _ b: String) -> Bool {
        let order = CursorRoles.groups.flatMap(\.keys).map { $0.lowercased() }
        let ia = order.firstIndex(of: CursorRoles.canonical(a)) ?? .max
        let ib = order.firstIndex(of: CursorRoles.canonical(b)) ?? .max
        return ia == ib ? a < b : ia < ib
    }

    private func parse() {
        do {
            let parsed = try CursorTheme.importSource(source, name: nil, pixelsPerPoint: pixelsPerPoint)
            // 適用時に初めて弾かれないよう、取り込む前に同じ検証を通す。
            _ = try parsed.theme.resolvedPlan()
            if !choosesScale { name = parsed.theme.name }
            result = .success(parsed)
        } catch {
            result = .failure(error)
        }
    }
}

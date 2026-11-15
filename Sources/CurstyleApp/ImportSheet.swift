import CursorKit
import SwiftUI

/// 取り込む前に、役割の対応・取り込まないファイルを見せ、試用エリアで見え方と大きさを確かめてもらう。
struct ImportSheet: View {
    let model: AppModel
    let source: URL

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var result: Result<(theme: CursorTheme, skipped: [String], adjustments: [String]), Error>?
    @State private var session: TryoutSession?
    @State private var saveError: String?

    init(model: AppModel, source: URL) {
        self.model = model
        self.source = source
        _name = State(initialValue: source.deletingPathExtension().lastPathComponent)
    }

    private var isCurstyleTheme: Bool {
        FileManager.default.fileExists(atPath: source.appendingPathComponent("theme.json").path)
    }

    private var isCape: Bool { source.pathExtension.lowercased() == "cape" }

    /// Windows のフォルダだけ、pt が決まっていないので 1 px = 1 pt で読み込む(大きさは試用画面の倍率で決める)。
    private var isWindowsFolder: Bool { !isCurstyleTheme && !isCape }

    var body: some View {
        VStack(spacing: 0) {
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
                Spacer()
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Text(L10n.text("名前"))
                        TextField(L10n.text("名前"), text: $name)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                    }
                    content
                }
                .padding(20)
            }
            Divider()
            HStack {
                if let saveError {
                    Label(L10n.text("追加できませんでした: {0}", saveError), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer()
                Button(L10n.text("キャンセル"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text("ライブラリに追加"), action: add)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
            .padding(20)
        }
        .frame(width: 640, height: 560)
        .task { parse() }
    }

    private var canAdd: Bool {
        guard case .success? = result, let session else { return false }
        return session.isCurrent && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        guard let session else { return }
        var theme = session.result
        theme.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try model.add(theme)
            dismiss()
        } catch {
            saveError = "\(error)"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch result {
        case .success(let parsed)?:
            if let session {
                ThemeTryoutView(
                    session: session,
                    note: isWindowsFolder ? L10n.text("Windows のカーソルは 1 px = 1 pt の大きさで読み込みます。") : nil)
                tiles(session.result)
            }
            ForEach(parsed.adjustments, id: \.self) { adjustment in
                Label(adjustment, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !parsed.skipped.isEmpty {
                Label(
                    L10n.text("取り込まないもの: {0}", String(describing: parsed.skipped.sorted().joined(separator: ", "))),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
            .frame(maxWidth: .infinity, minHeight: 200)
            .cardBackground()
        case nil:
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func tiles(_ theme: CursorTheme) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
            ForEach(theme.cursors.keys.sorted(by: tileOrder), id: \.self) { key in
                let rep = theme.cursors[key]!
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
    }

    private func tileOrder(_ a: String, _ b: String) -> Bool {
        let order = CursorRoles.groups.flatMap(\.keys).map { $0.lowercased() }
        let ia = order.firstIndex(of: CursorRoles.canonical(a)) ?? .max
        let ib = order.firstIndex(of: CursorRoles.canonical(b)) ?? .max
        return ia == ib ? a < b : ia < ib
    }

    private func parse() {
        do {
            let parsed = try CursorTheme.importSource(source, name: nil, pixelsPerPoint: 1)
            // 適用時に初めて弾かれないよう、取り込む前に同じ検証を通す。
            _ = try parsed.theme.resolvedPlan()
            if !isWindowsFolder { name = parsed.theme.name }
            session = TryoutSession(base: parsed.theme)
            result = .success(parsed)
        } catch {
            result = .failure(error)
        }
    }
}

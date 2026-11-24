import AppKit
import CursorKit
import SwiftUI
import UniformTypeIdentifiers

/// カーソル1つを、ライブラリの別テーマのカーソルか GIF / PNG に差し替える。左に「いま」、右に「変えた後」を並べて見比べ、
/// 保存するまでライブラリには書かない。テーマに無い役割を足すときも同じ画面を使う(`before` が nil)。
struct CursorReplaceSheet: View {
    enum Source: String, CaseIterable, Identifiable {
        case library, file
        var id: String { rawValue }
    }

    let model: AppModel
    let entry: ThemeLibrary.Entry
    let key: String

    @Environment(\.dismiss) private var dismiss
    @State private var source: Source = .library
    @State private var libraryID: String?
    @State private var libraryKey: String?
    @State private var matchesSize = true
    @State private var libraryRep: CursorRep?
    @State private var fileURL: URL?
    @State private var pointSize: Double
    @State private var fileRep: CursorRep?
    @State private var fileAdjustment: String?
    @State private var errorText: String?
    @State private var appliesToSiblings = true

    private let before: CursorRep?
    /// 同じ画像を共有しているキー(Windows の Horizontal は6つのサイズ変更に当たる、など)。
    private let siblings: [String]

    init(model: AppModel, entry: ThemeLibrary.Entry, key: String) {
        self.model = model
        self.entry = entry
        self.key = key
        let original = entry.theme.cursors[key]
        before = original
        _pointSize = State(initialValue: original.map { min(128, max(8, max($0.size.width, $0.size.height))) } ?? 32)
        let hash = original?.contentHash
        siblings =
            hash.map { hash in
                entry.theme.cursors.filter { $0.key != key && $0.value.contentHash == hash }.map(\.key).sorted()
            } ?? []
    }

    private var others: [ThemeLibrary.Entry] { model.entries.filter { $0.id != entry.id } }
    private var candidate: CursorRep? { source == .library ? libraryRep : fileRep }

    private var validationError: String? {
        guard let candidate else { return nil }
        do {
            try candidate.validate()
            return nil
        } catch {
            return "\(error)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(systemImage: before == nil ? "plus" : "arrow.left.arrow.right", tint: .indigo, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        before == nil
                            ? L10n.text("{0} を追加", String(describing: CursorRoles.title(for: key)))
                            : L10n.text("{0} を個別に変える", String(describing: CursorRoles.title(for: key)))
                    )
                    .font(.title3.weight(.semibold))
                    Text("\(entry.theme.name) · \(key)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            comparison

            Picker("", selection: $source) {
                Text(L10n.text("ライブラリのテーマから選ぶ")).tag(Source.library)
                Text(L10n.text("GIF / PNG から選ぶ")).tag(Source.file)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch source {
                case .library: libraryPicker
                case .file: filePicker
                }
            }
            .frame(height: 210, alignment: .top)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !siblings.isEmpty {
                Toggle(isOn: $appliesToSiblings) {
                    Text(L10n.text("同じ画像を使う {0} 件にも反映", String(describing: siblings.count)))
                    Text(siblings.map(CursorRoles.title(for:)).joined(separator: "、"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    model.undoEdit(entry)
                } label: {
                    Label(L10n.text("元に戻す"), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(ThemeActionButtonStyle())
                .keyboardShortcut("z", modifiers: .command)
                .disabled(entry.undoCount == 0 || model.busyMessage != nil)
                .help(L10n.text("直前の編集を取り消す (⌘Z)"))
                if let validationError {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                Spacer()
                Button(L10n.text("キャンセル"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(before == nil ? L10n.text("追加") : L10n.text("保存")) { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        candidate == nil || validationError != nil
                            || (source == .file && !(8...128).contains(pointSize)))
            }
        }
        .padding(20)
        .frame(width: 640)
        .onAppear {
            libraryID = others.first?.id
            if others.isEmpty { source = .file }
            selectDefaultLibraryKey()
        }
        .onChange(of: libraryID) {
            selectDefaultLibraryKey()
        }
        .onChange(of: libraryKey) { refreshLibrary() }
        .onChange(of: matchesSize) { refreshLibrary() }
        .onChange(of: pointSize) { loadFile() }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    fileURL = url
                    source = .file
                    loadFile()
                }
            }
            return true
        }
    }

    // MARK: 左右の比較

    private var comparison: some View {
        let longest = max(
            [before, candidate].compactMap { $0 }.map { max($0.size.width, $0.size.height) }.max() ?? 32, 1)
        let zoom = min(4, 110 / longest)
        return HStack(spacing: 12) {
            comparePanel(
                title: L10n.text("いま"), rep: before, zoom: zoom,
                placeholder: L10n.text("テーマに無い(適用時は macOS の標準)"))
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            comparePanel(
                title: L10n.text("変えた後"), rep: candidate, zoom: zoom,
                placeholder: L10n.text("下で選ぶとここに出ます"))
        }
    }

    private func comparePanel(title: String, rep: CursorRep?, zoom: CGFloat, placeholder: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            ZStack {
                BackdropView(backdrop: model.backdrop, cornerRadius: 12)
                if let rep {
                    CursorPreview(rep: rep, zoom: zoom, showsHotspot: model.showsHotspot)
                } else {
                    Text(placeholder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(8)
                }
            }
            .frame(height: 140)
            Text(rep.map(summary) ?? " ")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func summary(_ rep: CursorRep) -> String {
        "\(Int(rep.size.width))×\(Int(rep.size.height)) pt"
            + (rep.frameCount > 1 ? L10n.text(" · {0} コマ", String(describing: rep.frameCount)) : "")
    }

    // MARK: ライブラリから選ぶ

    private var libraryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            if others.isEmpty {
                Text(L10n.text("ほかのテーマがライブラリにありません。先にテーマを追加してください。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Picker(L10n.text("テーマ"), selection: $libraryID) {
                        ForEach(others) { Text($0.theme.name).tag(Optional($0.id)) }
                    }
                    .frame(maxWidth: 320)
                    if before != nil {
                        Toggle(L10n.text("今の大きさに合わせる"), isOn: $matchesSize)
                            .toggleStyle(.checkbox)
                    }
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 110), spacing: 8)], spacing: 8) {
                        ForEach(libraryKeys, id: \.self) { candidateKey in
                            libraryTile(candidateKey)
                        }
                    }
                    .padding(2)
                }
            }
        }
    }

    private var libraryEntry: ThemeLibrary.Entry? { others.first { $0.id == libraryID } }

    private var libraryKeys: [String] {
        guard let libraryEntry else { return [] }
        return CursorRoles.grouped(Array(libraryEntry.theme.cursors.keys)).flatMap(\.keys)
    }

    private func libraryTile(_ candidateKey: String) -> some View {
        let rep = libraryEntry!.theme.cursors[candidateKey]!
        let selected = candidateKey == libraryKey
        return Button {
            libraryKey = candidateKey
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    BackdropView(backdrop: model.backdrop, cornerRadius: 8)
                    CursorPreview(rep: rep, zoom: min(1.5, 40 / max(rep.size.width, rep.size.height)))
                }
                .frame(height: 52)
                Text(CursorRoles.title(for: candidateKey)).font(.caption2).lineLimit(1)
            }
            .padding(6)
            .cardBackground(cornerRadius: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Brand.accent, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CursorRoles.title(for: candidateKey))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 同じ役割(矢印なら矢印)を最初から選んでおく。無ければ先頭。
    private func selectDefaultLibraryKey() {
        let keys = libraryKeys
        let role = CursorRoles.canonical(key)
        libraryKey = keys.first { CursorRoles.canonical($0) == role } ?? keys.first
        refreshLibrary()
    }

    private func refreshLibrary() {
        guard let libraryEntry, let libraryKey, var rep = libraryEntry.theme.cursors[libraryKey] else {
            libraryRep = nil
            return
        }
        do {
            if matchesSize, let before {
                let factor =
                    max(before.size.width, before.size.height) / max(rep.size.width, rep.size.height)
                if abs(factor - 1) > 0.01 { rep = try rep.scalingSize(by: factor) }
            }
            libraryRep = rep
            errorText = nil
        } catch {
            libraryRep = nil
            errorText = "\(error)"
        }
    }

    // MARK: GIF / PNG から選ぶ

    private var filePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(L10n.text("GIF / PNG を選ぶ…"), action: chooseFile)
                if let fileURL {
                    Text(fileURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if fileURL != nil {
                HStack {
                    TextField(L10n.text("大きさ (pt)"), value: $pointSize, format: .number)
                        .frame(maxWidth: 180)
                    Stepper("", value: $pointSize, in: 8...128, step: 2).labelsHidden()
                }
                if !(8...128).contains(pointSize) {
                    Text(L10n.text("大きさは 8〜128 pt で指定してください"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                Text(L10n.text("ここへ GIF / PNG をドラッグしても選べます。GIF はアニメのまま使えます。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let fileAdjustment {
                Label(fileAdjustment, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if before == nil || fileURL != nil {
                Text(L10n.text("クリック位置(ホットスポット)は保存後、タイルを右クリックして「ホットスポット・速さを編集…」から調整できます。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.gif, .png]
        panel.allowsMultipleSelection = false
        panel.message = L10n.text("カーソルにする GIF(アニメ可)か PNG を選んでください")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        loadFile()
    }

    /// 差し替え前のホットスポットは、大きさの比で新しい画像に移す(左上の (0,0) に飛ばさない)。
    /// 大きさの欄は1文字ごとに値が変わる(「32」は 3 → 32)。途中の小さな値で作り直すとホットスポットが
    /// 丸めで崩れるので、範囲外の値では作り直さない。
    private func loadFile() {
        guard let fileURL, (8...128).contains(pointSize) else { return }
        do {
            let imported = try CursorRep.fromImageFile(fileURL, pointSize: pointSize)
            var made = imported.rep
            if let before {
                let ratio = max(made.size.width, made.size.height) / max(before.size.width, before.size.height)
                made.hotspot = CGPoint(
                    x: min((before.hotspot.x * ratio * 2).rounded() / 2, made.size.width),
                    y: min((before.hotspot.y * ratio * 2).rounded() / 2, made.size.height))
            } else if !["arrow", "pointinghand"].contains(CursorRoles.canonical(key)) {
                // 先端で指す矢印とリンク以外は、中心が自然なクリック位置。
                made.hotspot = CGPoint(
                    x: (made.size.width / 2 * 2).rounded() / 2, y: (made.size.height / 2 * 2).rounded() / 2)
            }
            fileRep = made
            fileAdjustment = imported.adjustment
            errorText = nil
        } catch {
            fileRep = nil
            fileAdjustment = nil
            errorText = "\(error)"
        }
    }

    private func save() {
        guard let candidate else { return }
        var theme = entry.theme
        theme.cursors[key] = candidate
        if appliesToSiblings {
            for sibling in siblings { theme.cursors[sibling] = candidate }
        }
        if model.update(entry, with: theme) { dismiss() }
    }
}

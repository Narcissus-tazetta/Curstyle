import CursorKit
import SwiftUI

struct ThemeDetailView: View {
    @Bindable var model: AppModel
    let entry: ThemeLibrary.Entry

    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var confirmsDelete = false
    @State private var editingKey: EditingKey?
    @State private var editsSpeed = false
    @FocusState private var nameFocused: Bool

    private var isActive: Bool { model.isActive(entry) }
    private var hasPendingChanges: Bool { model.hasPendingChanges(entry) }

    private struct EditingKey: Identifiable {
        let key: String
        var id: String { key }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                ForEach(CursorRoles.grouped(Array(entry.theme.cursors.keys)), id: \.group.id) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.group.title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 10)], spacing: 10)
                        {
                            ForEach(section.keys, id: \.self) { key in
                                Button {
                                    editingKey = EditingKey(key: key)
                                } label: {
                                    CursorTile(
                                        key: key, rep: entry.theme.cursors[key]!, backdrop: model.backdrop,
                                        showsHotspot: model.showsHotspot)
                                }
                                .buttonStyle(.plain)
                                .disabled(model.busyMessage != nil)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(entry.theme.name)
        .toolbar {
            ToolbarItemGroup {
                Picker("背景", selection: $model.backdrop) {
                    ForEach(PreviewBackdrop.allCases) { backdrop in
                        // ツールバーの区切りボタンは記号の名前を読み上げるので、表示名を明示する。
                        Image(systemName: backdrop.systemImage)
                            .accessibilityLabel("背景: \(backdrop.title)")
                            .help("背景: \(backdrop.title)")
                            .tag(backdrop)
                    }
                }
                .pickerStyle(.segmented)
                .help("プレビューの背景")
                Toggle(isOn: $model.showsHotspot.animation(Motion.quick)) {
                    Label("ホットスポット", systemImage: "scope")
                }
                .iconHelp("クリック位置(ホットスポット)を表示")
            }
        }
        .sheet(item: $editingKey) { editing in
            CursorEditorSheet(model: model, entry: entry, key: editing.key)
        }
        .sheet(isPresented: $editsSpeed) {
            AnimationSpeedSheet(model: model, entry: entry)
        }
        .confirmationDialog(
            "「\(entry.theme.name)」をゴミ箱に入れますか?", isPresented: $confirmsDelete, titleVisibility: .visible
        ) {
            Button("ゴミ箱に入れる", role: .destructive) { model.remove(entry) }
        } message: {
            Text(isActive ? "適用中のカーソルはそのまま残ります。標準に戻すには「標準に戻す」を使ってください。" : "Finder のゴミ箱から戻せます。")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                BackdropView(backdrop: model.backdrop, cornerRadius: 14)
                if let rep = CursorRoles.representative(of: entry.theme) {
                    let zoom = min(3, 96 / max(rep.size.width, rep.size.height))
                    CursorPreview(rep: rep, zoom: zoom, showsHotspot: model.showsHotspot)
                }
            }
            .frame(width: 136, height: 136)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if isRenaming {
                        TextField("テーマ名", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: 320)
                            .focused($nameFocused)
                            .onSubmit(commitRename)
                            .onExitCommand { isRenaming = false }
                    } else {
                        Text(entry.theme.name)
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)
                        Button {
                            draftName = entry.theme.name
                            isRenaming = true
                            nameFocused = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .iconHelp("名前を変更")
                    }
                }
                HStack(spacing: 6) {
                    if isActive {
                        StatusPill(text: "適用中", systemImage: "checkmark.circle.fill")
                    } else if hasPendingChanges {
                        StatusPill(text: "適用中のものと内容が違います", systemImage: "exclamationmark.circle.fill", tint: .orange)
                    }
                    if let frames = maxFrames, frames > 1 {
                        StatusPill(text: "アニメ \(frames) コマ", systemImage: "film", tint: .cyan)
                    }
                    StatusPill(text: "\(entry.theme.cursors.count) 種類", systemImage: "cursorarrow", tint: .secondary)
                    StatusPill(text: sizeText, systemImage: "arrow.up.left.and.arrow.down.right", tint: .secondary)
                }
                Text("追加日 \(entry.addedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if hasPendingChanges {
                        Button {
                            Task { await model.apply(entry) }
                        } label: {
                            Label("変更を適用", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    if isActive || hasPendingChanges {
                        Button {
                            Task { await model.restore() }
                        } label: {
                            Label("標準に戻す", systemImage: "arrow.uturn.backward")
                        }
                        .controlSize(.large)
                    } else {
                        Button {
                            Task { await model.apply(entry) }
                        } label: {
                            Label("このテーマを適用", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    if let message = model.busyMessage {
                        ProgressView().controlSize(.small)
                        Text(message).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        if maxFrames ?? 1 > 1 {
                            Button("アニメの速さを一括で変える…") { editsSpeed = true }
                        }
                        Button("Finder で表示") { model.reveal(entry.directory) }
                        Divider()
                        Button("ゴミ箱に入れる…", role: .destructive) { confirmsDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("その他の操作")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .iconHelp("その他の操作")
                }
                .disabled(model.busyMessage != nil)
            }
            .frame(maxHeight: 136)
        }
        .padding(16)
        .cardBackground(cornerRadius: 16)
    }

    private var maxFrames: Int? { entry.theme.cursors.values.map(\.frameCount).max() }

    private var sizeText: String {
        let sizes = Set(entry.theme.cursors.values.map { Int(max($0.size.width, $0.size.height)) })
        guard let low = sizes.min(), let high = sizes.max() else { return "-" }
        return low == high ? "\(low) pt" : "\(low)〜\(high) pt"
    }

    private func commitRename() {
        model.rename(entry, to: draftName)
        isRenaming = false
    }
}

private struct CursorTile: View {
    let key: String
    let rep: CursorRep
    let backdrop: PreviewBackdrop
    let showsHotspot: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                BackdropView(backdrop: backdrop)
                let zoom = min(2, 64 / max(rep.size.width, rep.size.height))
                CursorPreview(rep: rep, zoom: zoom, showsHotspot: showsHotspot)
            }
            .frame(height: 92)
            VStack(spacing: 1) {
                Text(CursorRoles.title(for: key))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .cardBackground()
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isHovered ? 0.5 : 0), lineWidth: 1.5)
        )
        .onHover { isHovered = $0 }
        .motionAnimation(Motion.quick, value: isHovered)
        .help(
            "クリックで編集\n\(key)\n\(Int(rep.size.width))×\(Int(rep.size.height)) pt · ホットスポット (\(fmt(rep.hotspot.x)), \(fmt(rep.hotspot.y)))"
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(CursorRoles.title(for: key))、\(detail)")
    }

    private var detail: String {
        rep.frameCount > 1
            ? "\(rep.frameCount) コマ · \(String(format: "%.2f", rep.frameDuration)) 秒" : "静止画"
    }

    private func fmt(_ v: CGFloat) -> String { v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v) }
}

struct EmptyLibraryView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("カーソルテーマを追加しましょう")
                .font(.title3.weight(.semibold))
            Text("Windows のカーソルテーマ(.ani / .cur)のフォルダか .cape ファイルをここへドラッグするか、下のボタンから選んでください。取り込んだテーマは適用する前にプレビューできます。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                chooseImportFolder(model: model)
            } label: {
                Label("フォルダ・ファイルを選ぶ", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if let name = model.activeOutsideLibrary {
                Text("いま「\(name)」が適用されています(ライブラリの外で適用したテーマ)。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
        .padding(40)
    }
}

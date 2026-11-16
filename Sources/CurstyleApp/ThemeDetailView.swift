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
    @State private var triesOut = false
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
                Picker(L10n.text("背景"), selection: $model.backdrop) {
                    ForEach(PreviewBackdrop.allCases) { backdrop in
                        // ツールバーの区切りボタンは記号の名前を読み上げるので、表示名を明示する。
                        Image(systemName: backdrop.systemImage)
                            .accessibilityLabel(L10n.text("背景: {0}", String(describing: backdrop.title)))
                            .help(L10n.text("背景: {0}", String(describing: backdrop.title)))
                            .tag(backdrop)
                    }
                }
                .pickerStyle(.segmented)
                .help(L10n.text("プレビューの背景"))
                Toggle(isOn: $model.showsHotspot.animation(Motion.quick)) {
                    Label(L10n.text("ホットスポット"), systemImage: "scope")
                }
                .iconHelp(L10n.text("クリック位置(ホットスポット)を表示"))
            }
        }
        .sheet(item: $editingKey) { editing in
            CursorEditorSheet(model: model, entry: entry, key: editing.key)
        }
        .sheet(isPresented: $triesOut) {
            ThemeTryoutSheet(model: model, entry: entry)
        }
        .sheet(isPresented: $editsSpeed) {
            AnimationSpeedSheet(model: model, entry: entry)
        }
        .confirmationDialog(
            L10n.text("「{0}」をゴミ箱に入れますか?", String(describing: entry.theme.name)), isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button(L10n.text("ゴミ箱に入れる"), role: .destructive) { model.remove(entry) }
        } message: {
            Text(isActive ? L10n.text("適用中のカーソルはそのまま残ります。標準に戻すには「標準に戻す」を使ってください。") : L10n.text("Finder のゴミ箱から戻せます。"))
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
                        TextField(L10n.text("テーマ名"), text: $draftName)
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
                        .iconHelp(L10n.text("名前を変更"))
                    }
                }
                HStack(spacing: 6) {
                    if isActive {
                        StatusPill(text: L10n.text("適用中"), systemImage: "checkmark.circle.fill")
                    } else if hasPendingChanges {
                        StatusPill(
                            text: L10n.text("適用中のものと内容が違います"), systemImage: "exclamationmark.circle.fill", tint: .orange
                        )
                    }
                    if let frames = maxFrames, frames > 1 {
                        StatusPill(
                            text: L10n.text("アニメ {0} コマ", String(describing: frames)), systemImage: "film", tint: .cyan)
                    }
                    StatusPill(
                        text: L10n.text("{0} 種類", String(describing: entry.theme.cursors.count)),
                        systemImage: "cursorarrow", tint: .secondary)
                    StatusPill(text: sizeText, systemImage: "arrow.up.left.and.arrow.down.right", tint: .secondary)
                }
                Text(
                    L10n.text(
                        "追加日 {0}",
                        String(
                            describing: entry.addedAt.formatted(
                                Date.FormatStyle(date: .abbreviated, time: .shortened).locale(
                                    Locale(identifier: L10n.language)))))
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if hasPendingChanges {
                        Button {
                            Task { await model.apply(entry) }
                        } label: {
                            Label(L10n.text("変更を適用"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    if isActive || hasPendingChanges {
                        Button {
                            Task { await model.restore() }
                        } label: {
                            Label(L10n.text("標準に戻す"), systemImage: "arrow.uturn.backward")
                        }
                        .controlSize(.large)
                    } else {
                        Button {
                            Task { await model.apply(entry) }
                        } label: {
                            Label(L10n.text("このテーマを適用"), systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    Button {
                        triesOut = true
                    } label: {
                        Label(L10n.text("試してみる"), systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.large)
                    if let message = model.busyMessage {
                        ProgressView().controlSize(.small)
                        Text(message).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button(L10n.text("試して整える…")) { triesOut = true }
                        if maxFrames ?? 1 > 1 {
                            Button(L10n.text("アニメの速さを一括で変える…")) { editsSpeed = true }
                        }
                        Button(L10n.text("Finder で表示")) { model.reveal(entry.directory) }
                        Divider()
                        Button(L10n.text("ゴミ箱に入れる…"), role: .destructive) { confirmsDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel(L10n.text("その他の操作"))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .iconHelp(L10n.text("その他の操作"))
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
        return low == high
            ? "\(low) pt" : L10n.text("{0}〜{1} pt", String(describing: low), String(describing: high))
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
            L10n.text(
                "クリックで編集\n{0}\n{1}×{2} pt · ホットスポット ({3}, {4})", String(describing: key),
                String(describing: Int(rep.size.width)), String(describing: Int(rep.size.height)),
                String(describing: fmt(rep.hotspot.x)), String(describing: fmt(rep.hotspot.y)))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.text("{0}、{1}", String(describing: CursorRoles.title(for: key)), String(describing: detail)))
    }

    private var detail: String {
        rep.frameCount > 1
            ? L10n.text(
                "{0} コマ · {1} 秒", String(describing: rep.frameCount),
                String(describing: String(format: "%.2f", rep.frameDuration))) : L10n.text("静止画")
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
            Text(L10n.text("カーソルテーマを追加しましょう"))
                .font(.title3.weight(.semibold))
            Text(
                L10n.text(
                    "Windows のカーソルテーマ(.ani / .cur)のフォルダか .cape ファイルをここへドラッグするか、下のボタンから選んでください。取り込んだテーマは適用する前にプレビューできます。"
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                chooseImportFolder(model: model)
            } label: {
                Label(L10n.text("フォルダ・ファイルを選ぶ"), systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if let name = model.activeOutsideLibrary {
                Text(L10n.text("いま「{0}」が適用されています(ライブラリの外で適用したテーマ)。", String(describing: name)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
        .padding(40)
    }
}

import CursorKit
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            Section("テーマ") {
                ForEach(model.entries) { entry in
                    ThemeRow(entry: entry, isActive: model.isActive(entry))
                        .tag(SidebarItem.theme(entry.id))
                        .contextMenu { ThemeActionsMenu(model: model, entry: entry) }
                }
                if model.entries.isEmpty {
                    Text("まだテーマがありません")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
            }
            Section("ツール") {
                Label {
                    HStack {
                        Text("診断")
                        Spacer()
                        if model.warningCount > 0 {
                            Text("\(model.warningCount)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.orange, in: Capsule())
                                .accessibilityLabel("警告 \(model.warningCount) 件")
                        }
                    }
                } icon: {
                    IconTile(systemImage: "stethoscope", tint: .teal)
                }
                .tag(SidebarItem.diagnostics)
                Label {
                    Text("設定")
                } icon: {
                    IconTile(systemImage: "gearshape.fill", tint: .gray)
                }
                .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusFooter(model: model)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    chooseImportFolder(model: model)
                } label: {
                    Label("テーマを取り込む", systemImage: "plus")
                }
                .iconHelp("テーマを取り込む")
            }
        }
    }
}

private struct ThemeRow: View {
    let entry: ThemeLibrary.Entry
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: 0.88))
                if let rep = CursorRoles.representative(of: entry.theme) {
                    let zoom = min(1, 22 / max(rep.size.width, rep.size.height))
                    CursorPreview(rep: rep, zoom: zoom, animates: false)
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.theme.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("適用中")
                    .help("適用中")
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let animated = entry.theme.cursors.values.contains { $0.frameCount > 1 }
        return "\(entry.theme.cursors.count) 種類\(animated ? " · アニメ" : "")"
    }
}

/// サイドバーの下端に、いまの状態(適用中のテーマ・ヘルパー)を常に出しておく。
private struct StatusFooter: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 8) {
                Circle()
                    .fill(model.journal.status == .applied ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.statusSummary)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(helperText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if model.journal.status != .clean {
                    Button {
                        Task { await model.restore() }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.busyMessage != nil)
                    .iconHelp("標準のカーソルに戻す")
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .accessibilityElement(children: .contain)
    }

    private var helperText: String {
        if model.helperState.stoppedReason != nil { return "自動再適用: 停止中" }
        switch model.helperService {
        case .enabled: return "自動再適用: オン"
        case .requiresApproval: return "自動再適用: 承認待ち"
        case .disabled, .unavailable:
            return model.hasLegacyHelper ? "自動再適用: オン(CLI で登録)" : "自動再適用: オフ"
        }
    }
}

struct ThemeActionsMenu: View {
    let model: AppModel
    let entry: ThemeLibrary.Entry

    var body: some View {
        Button("適用") { Task { await model.apply(entry) } }
            .disabled(model.busyMessage != nil || model.isActive(entry))
        Divider()
        Button("Finder で表示") { model.reveal(entry.directory) }
        Divider()
        Button("ゴミ箱に入れる", role: .destructive) { model.remove(entry) }
    }
}

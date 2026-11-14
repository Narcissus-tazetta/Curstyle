import CursorKit
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: themeSelection) {
            Section(L10n.text("テーマ")) {
                ForEach(model.entries) { entry in
                    ThemeRow(entry: entry, isActive: model.isActive(entry))
                        .tag(entry.id)
                        .contextMenu { ThemeActionsMenu(model: model, entry: entry) }
                }
                if model.entries.isEmpty {
                    Text(L10n.text("まだテーマがありません"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
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
                    Label(L10n.text("テーマを取り込む"), systemImage: "plus")
                }
                .iconHelp(L10n.text("テーマを取り込む"))
            }
        }
    }

    private var themeSelection: Binding<String?> {
        Binding(
            get: {
                if case .theme(let id) = model.selection { return id }
                return nil
            },
            set: { id in
                if let id { model.selection = .theme(id) }
            }
        )
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
                    CursorPreview(rep: rep, zoom: zoom)
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
                    .accessibilityLabel(L10n.text("適用中"))
                    .help(L10n.text("適用中"))
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let animated = entry.theme.cursors.values.contains { $0.frameCount > 1 }
        return L10n.text(
            "{0} 種類{1}", String(describing: entry.theme.cursors.count),
            String(describing: animated ? L10n.text(" · アニメ") : ""))
    }
}

/// サイドバーの下端に、設定と現在の状態(適用中のテーマ・ヘルパー)を常に出しておく。
private struct StatusFooter: View {
    @Bindable var model: AppModel
    @State private var isHoveringSettings = false

    private var isSettingsSelected: Bool { model.selection == .settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.selection = .settings
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSettingsSelected ? .primary : .secondary)
                        .frame(width: 18)
                    Text(L10n.text("設定"))
                        .font(.body)
                    Spacer(minLength: 4)
                    if model.warningCount > 0 {
                        Text("\(model.warningCount)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange, in: Capsule())
                            .accessibilityLabel(L10n.text("警告 {0} 件", String(describing: model.warningCount)))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(isSettingsSelected ? 0.11 : isHoveringSettings ? 0.05 : 0))
                )
            }
            .buttonStyle(.plain)
            .onHover { isHoveringSettings = $0 }
            .padding(.horizontal, 10)
            .padding(.top, 4)

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
                    .iconHelp(L10n.text("標準のカーソルに戻す"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .accessibilityElement(children: .contain)
    }

    private var helperText: String {
        if model.helperState.stoppedReason != nil { return L10n.text("自動再適用: 停止中") }
        switch model.helperService {
        case .enabled: return L10n.text("自動再適用: オン")
        case .requiresApproval: return L10n.text("自動再適用: 承認待ち")
        case .disabled, .unavailable:
            return model.hasLegacyHelper ? L10n.text("自動再適用: オン(CLI で登録)") : L10n.text("自動再適用: オフ")
        }
    }
}

struct ThemeActionsMenu: View {
    let model: AppModel
    let entry: ThemeLibrary.Entry

    var body: some View {
        Button(L10n.text("適用")) { Task { await model.apply(entry) } }
            .disabled(model.busyMessage != nil || model.isActive(entry))
        Divider()
        Button(L10n.text("Finder で表示")) { model.reveal(entry.directory) }
        Divider()
        Button(L10n.text("ゴミ箱に入れる"), role: .destructive) { model.remove(entry) }
    }
}

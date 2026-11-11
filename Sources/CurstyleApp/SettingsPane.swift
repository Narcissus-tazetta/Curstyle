import CursorKit
import ServiceManagement
import SwiftUI

struct SettingsPane: View {
    @Bindable var model: AppModel
    @AppStorage(L10n.preferenceKey, store: L10n.preferences) private var language = ""
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var showsDiagnostics = false
    @State private var showsPerName = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.helperService == .enabled || model.helperService == .requiresApproval },
                            set: { model.setHelperEnabled($0) })
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(model.helperService == .unavailable)
                } label: {
                    settingLabel(
                        L10n.text("テーマが消えたら自動で入れ直す"), systemImage: "arrow.triangle.2.circlepath", tint: .blue,
                        detail: L10n.text("再ログイン・再起動・ポインター設定の変更でテーマが消えたとき、常駐ヘルパーが入れ直します。"))
                }
                if model.helperService == .requiresApproval {
                    notice(
                        L10n.text("システム設定の「ログイン項目」で Curstyle のバックグラウンド実行を許可してください。"),
                        systemImage: "hand.raised.fill", tint: .orange
                    ) {
                        Button(L10n.text("システム設定を開く")) { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if model.helperService == .unavailable {
                    notice(
                        L10n.text("ヘルパーの登録は Curstyle.app として起動したときだけ使えます(make-app.sh で組み立てたもの)。"),
                        systemImage: "info.circle.fill", tint: .secondary)
                }
                if model.hasLegacyHelper {
                    notice(
                        L10n.text("`curstyle helper install` で登録したヘルパーが動いています。上のスイッチをオンにすると、アプリ同梱のヘルパーに置き換えます。"),
                        systemImage: "info.circle.fill", tint: .blue)
                }
                if let reason = model.helperState.stoppedReason {
                    notice(
                        L10n.text("自動再適用は止まっています: {0}", String(describing: reason)), systemImage: "pause.circle.fill",
                        tint: .orange
                    ) {
                        Button(L10n.text("再開")) { model.resumeHelper() }
                    }
                }
                if let at = model.helperState.lastCheckAt {
                    LabeledContent(L10n.text("直近の確認")) {
                        Text(
                            "\(at.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(Locale(identifier: L10n.language)))) \(model.helperState.lastResult ?? "")"
                        )
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    }
                }
            } header: {
                Text(L10n.text("常駐ヘルパー"))
            }

            Section(L10n.text("アプリ")) {
                Picker(
                    L10n.text("言語"),
                    selection: Binding(
                        get: { language.isEmpty ? L10n.language : language },
                        set: { L10n.setLanguage($0) }
                    )
                ) {
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "日本語").tag("ja")
                }
                Text(L10n.text("システムのメニューやダイアログには、アプリの再起動後に反映されます。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent {
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                try LaunchAtLogin.setEnabled(enabled)
                            } catch {
                                model.show(.failure, L10n.text("ログイン項目を変更できませんでした"), "\(error)")
                            }
                            // 要求した値ではなく OS が実際に返す値を見せる。
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                } label: {
                    settingLabel(
                        L10n.text("ログイン時にメニューバーに表示"), systemImage: "menubar.rectangle", tint: .indigo,
                        detail: L10n.text("テーマの切り替えと「標準に戻す」をメニューバーから使えます。自動再適用には不要です。"))
                }
            }

            Section(L10n.text("保存場所")) {
                LabeledContent {
                    Button(L10n.text("Finder で表示")) { model.reveal(model.library.root) }
                } label: {
                    settingLabel(
                        L10n.text("テーマのライブラリ"), systemImage: "folder.fill", tint: .cyan,
                        detail: model.library.root.path(percentEncoded: false))
                }
                LabeledContent {
                    Button(L10n.text("Finder で表示")) { model.reveal(model.store.root) }
                } label: {
                    settingLabel(
                        L10n.text("スナップショットと記録"), systemImage: "externaldrive.fill", tint: .gray,
                        detail: L10n.text("標準のカーソルの写し・適用の記録・ヘルパーのログ。"))
                }
            }

            Section {
                LabeledContent {
                    Button(L10n.text("標準に戻す")) { Task { await model.restore() } }
                        .disabled(model.journal.status == .clean || model.busyMessage != nil)
                } label: {
                    settingLabel(
                        L10n.text("標準のカーソルに戻す"), systemImage: "arrow.uturn.backward", tint: .red,
                        detail: L10n.text("アプリが起動しないときは、ターミナルで `curstyle restore` でも戻せます。"))
                }
            } header: {
                Text(L10n.text("復元"))
            }

            Section(L10n.text("診断")) {
                let count = model.warningCount
                LabeledContent {
                    HStack(spacing: 8) {
                        if model.isDiagnosing {
                            ProgressView().controlSize(.small)
                        }
                        Button(L10n.text("もう一度診断")) {
                            Task { await model.runDiagnostics() }
                        }
                        .disabled(model.isDiagnosing)
                        Button(L10n.text("レポートを書き出す")) {
                            model.exportReport()
                        }
                    }
                } label: {
                    settingLabel(
                        model.diagnostics == nil
                            ? L10n.text("診断しています…")
                            : count == 0
                                ? L10n.text("問題は見つかりませんでした") : L10n.text("{0} 件の確認が必要です", String(describing: count)),
                        systemImage: count == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        tint: count == 0 ? .green : .orange,
                        detail: L10n.text("読み戻しが一致しても、画面に表示された証拠にはなりません。見た目は実際にカーソルを動かして確かめてください。"))
                }
                if let report = model.diagnostics {
                    let problems = report.items.filter { $0.level != .ok }
                    // 名前ごとの状態(com.apple.*)は数が多いので別枠で折りたたむ。
                    let fine = report.items.filter { $0.level == .ok && !$0.title.hasPrefix("com.apple.") }
                    let perName = report.items.filter { $0.level == .ok && $0.title.hasPrefix("com.apple.") }
                    ForEach(Array(problems.enumerated()), id: \.offset) { _, item in
                        DiagnosticRow(item: item)
                    }
                    if !fine.isEmpty {
                        DisclosureGroup(isExpanded: $showsDiagnostics) {
                            ForEach(Array(fine.enumerated()), id: \.offset) { _, item in
                                DiagnosticRow(item: item)
                            }
                        } label: {
                            Text(L10n.text("診断の内訳({0} 件)", String(describing: fine.count)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(Motion.quick) { showsDiagnostics.toggle() }
                                }
                        }
                    }
                    if !perName.isEmpty {
                        DisclosureGroup(isExpanded: $showsPerName) {
                            ForEach(Array(perName.enumerated()), id: \.offset) { _, item in
                                DiagnosticRow(item: item)
                            }
                        } label: {
                            Text(L10n.text("カーソル名ごとの状態({0} 件)", String(describing: perName.count)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(Motion.quick) { showsPerName.toggle() }
                                }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L10n.text("設定"))
        .onAppear {
            model.refreshStatus()
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private func settingLabel(_ title: String, systemImage: String, tint: Color, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            IconTile(systemImage: systemImage, tint: tint, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private func notice(
        _ text: String, systemImage: String, tint: Color,
        @ViewBuilder action: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            action()
        }
        .transition(Motion.reveal)
    }
}

private struct DiagnosticRow: View {
    let item: DiagnosticReport.Item

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityLabel(L10n.text(item.level.rawValue))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.callout.weight(.medium))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch item.level {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch item.level {
        case .ok: .green
        case .warning: .yellow
        case .error: .red
        }
    }
}

import CursorKit
import ServiceManagement
import SwiftUI

struct SettingsPane: View {
    @Bindable var model: AppModel
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
                        "テーマが消えたら自動で入れ直す", systemImage: "arrow.triangle.2.circlepath", tint: .blue,
                        detail: "再ログイン・再起動・ポインター設定の変更でテーマが消えたとき、常駐ヘルパーが入れ直します。")
                }
                if model.helperService == .requiresApproval {
                    notice(
                        "システム設定の「ログイン項目」で Curstyle のバックグラウンド実行を許可してください。",
                        systemImage: "hand.raised.fill", tint: .orange
                    ) {
                        Button("システム設定を開く") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if model.helperService == .unavailable {
                    notice(
                        "ヘルパーの登録は Curstyle.app として起動したときだけ使えます(make-app.sh で組み立てたもの)。",
                        systemImage: "info.circle.fill", tint: .secondary)
                }
                if model.hasLegacyHelper {
                    notice(
                        "`curstyle helper install` で登録したヘルパーが動いています。上のスイッチをオンにすると、アプリ同梱のヘルパーに置き換えます。",
                        systemImage: "info.circle.fill", tint: .blue)
                }
                if let reason = model.helperState.stoppedReason {
                    notice("自動再適用は止まっています: \(reason)", systemImage: "pause.circle.fill", tint: .orange) {
                        Button("再開") { model.resumeHelper() }
                    }
                }
                if let at = model.helperState.lastCheckAt {
                    LabeledContent("直近の確認") {
                        Text(
                            "\(at.formatted(date: .abbreviated, time: .standard)) \(model.helperState.lastResult ?? "")"
                        )
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    }
                }
            } header: {
                Text("常駐ヘルパー")
            }

            Section("アプリ") {
                LabeledContent {
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                try LaunchAtLogin.setEnabled(enabled)
                            } catch {
                                model.show(.failure, "ログイン項目を変更できませんでした", "\(error)")
                            }
                            // 要求した値ではなく OS が実際に返す値を見せる。
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                } label: {
                    settingLabel(
                        "ログイン時にメニューバーに表示", systemImage: "menubar.rectangle", tint: .indigo,
                        detail: "テーマの切り替えと「標準に戻す」をメニューバーから使えます。自動再適用には不要です。")
                }
            }

            Section("保存場所") {
                LabeledContent {
                    Button("Finder で表示") { model.reveal(model.library.root) }
                } label: {
                    settingLabel(
                        "テーマのライブラリ", systemImage: "folder.fill", tint: .cyan,
                        detail: model.library.root.path(percentEncoded: false))
                }
                LabeledContent {
                    Button("Finder で表示") { model.reveal(model.store.root) }
                } label: {
                    settingLabel(
                        "スナップショットと記録", systemImage: "externaldrive.fill", tint: .gray,
                        detail: "標準のカーソルの写し・適用の記録・ヘルパーのログ。")
                }
            }

            Section {
                LabeledContent {
                    Button("標準に戻す") { Task { await model.restore() } }
                        .disabled(model.journal.status == .clean || model.busyMessage != nil)
                } label: {
                    settingLabel(
                        "標準のカーソルに戻す", systemImage: "arrow.uturn.backward", tint: .red,
                        detail: "アプリが起動しないときは、ターミナルで `curstyle restore` でも戻せます。")
                }
            } header: {
                Text("復元")
            }

            Section("診断") {
                let count = model.warningCount
                LabeledContent {
                    HStack(spacing: 8) {
                        if model.isDiagnosing {
                            ProgressView().controlSize(.small)
                        }
                        Button("もう一度診断") {
                            Task { await model.runDiagnostics() }
                        }
                        .disabled(model.isDiagnosing)
                        Button("レポートを書き出す") {
                            model.exportReport()
                        }
                    }
                } label: {
                    settingLabel(
                        model.diagnostics == nil ? "診断しています…" : count == 0 ? "問題は見つかりませんでした" : "\(count) 件の確認が必要です",
                        systemImage: count == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        tint: count == 0 ? .green : .orange,
                        detail: "読み戻しが一致しても、画面に表示された証拠にはなりません。見た目は実際にカーソルを動かして確かめてください。")
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
                            Text("診断の内訳(\(fine.count) 件)")
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
                            Text("カーソル名ごとの状態(\(perName.count) 件)")
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
        .navigationTitle("設定")
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
            Text(LocalizedStringKey(text))
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
                .accessibilityLabel(item.level.rawValue)
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

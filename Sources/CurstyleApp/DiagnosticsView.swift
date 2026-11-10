import CursorKit
import SwiftUI

struct DiagnosticsView: View {
    @Bindable var model: AppModel
    @State private var showsPerName = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary
                if let report = model.diagnostics {
                    let problems = report.items.filter { $0.level != .ok }
                    // 名前ごとの状態(com.apple.*)は数が多いので、問題が無いものは折りたたむ。
                    let fine = report.items.filter { $0.level == .ok && !$0.title.hasPrefix("com.apple.") }
                    let perName = report.items.filter { $0.level == .ok && $0.title.hasPrefix("com.apple.") }
                    if !problems.isEmpty { section("確認が必要", problems) }
                    section("問題なし", fine)
                    if !perName.isEmpty {
                        DisclosureGroup(isExpanded: $showsPerName) {
                            rows(perName).padding(.top, 8)
                        } label: {
                            Text("カーソル名ごとの状態(\(perName.count) 件)")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("診断")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.runDiagnostics() }
                } label: {
                    Label("もう一度診断", systemImage: "arrow.clockwise")
                }
                .iconHelp("もう一度診断")
                .disabled(model.isDiagnosing)
                Button {
                    model.exportReport()
                } label: {
                    Label("レポートを書き出す", systemImage: "square.and.arrow.up")
                }
                .iconHelp("不具合報告用のレポートを書き出す")
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            let count = model.warningCount
            IconTile(
                systemImage: count == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                tint: count == 0 ? .green : .orange, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.diagnostics == nil ? "診断しています…" : count == 0 ? "問題は見つかりませんでした" : "\(count) 件の確認が必要です")
                    .font(.title3.weight(.semibold))
                Text("読み戻しが一致しても、画面に表示された証拠にはなりません。見た目は実際にカーソルを動かして確かめてください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if model.isDiagnosing { ProgressView().controlSize(.small) }
        }
        .padding(16)
        .cardBackground(cornerRadius: 16)
    }

    private func section(_ title: String, _ items: [DiagnosticReport.Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            rows(items)
        }
    }

    private func rows(_ items: [DiagnosticReport.Item]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider().padding(.leading, 40) }
                DiagnosticRow(item: item)
            }
        }
        .cardBackground()
    }
}

private struct DiagnosticRow: View {
    let item: DiagnosticReport.Item

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

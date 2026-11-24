import CursorKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var model: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 320)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // 開閉中は分割ビューの要求幅が窓幅を超えるため、中央揃えだと列全体が左へずれる。
        .frame(minWidth: 820, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if let banner = model.banner {
                BannerView(banner: banner) { model.banner = nil }
                    .padding(.top, 10)
                    .transition(Motion.reveal)
                    .id(banner.id)
            }
        }
        .motionAnimation(value: model.banner)
        .overlay {
            if isDropTargeted {
                DropTargetOverlay()
                    .transition(.opacity)
            }
        }
        .motionAnimation(Motion.quick, value: isDropTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.importSource = url }
            }
            return true
        }
        .sheet(item: $model.importSource) { url in
            ImportSheet(model: model, source: url)
        }
        .task { await model.runDiagnostics() }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .theme(let id)?:
            if let entry = model.entry(id: id) {
                ThemeDetailView(model: model, entry: entry)
                    .id(entry.id)
            } else {
                EmptyLibraryView(model: model)
            }
        case .settings?:
            SettingsPane(model: model)
        case nil:
            EmptyLibraryView(model: model)
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

@MainActor
func chooseImportFolder(model: AppModel) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowedContentTypes = [.folder, UTType(filenameExtension: "cape") ?? .propertyList]
    panel.allowsMultipleSelection = false
    panel.prompt = L10n.text("選択")
    panel.message = L10n.text("Windows のカーソルテーマ(.ani / .cur)のフォルダ、.cape ファイル、Curstyle のテーマ(theme.json)のフォルダを選んでください")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    model.importSource = url
}

private struct BannerView: View {
    let banner: Banner
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title).font(.callout.weight(.semibold))
                if let detail = banner.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .buttonStyle(.borderless)
            .iconHelp(L10n.text("閉じる"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 520)
        .glassOrMaterial(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: banner.id) {
            // 失敗は読み終えるまで残す。成功・情報は数秒で消す。
            guard banner.kind != .failure else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { dismiss() }
        }
    }

    private var icon: String {
        switch banner.kind {
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch banner.kind {
        case .success: .green
        case .failure: .orange
        case .info: Brand.accent
        }
    }
}

private struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            Brand.accent.opacity(0.08)
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 40, weight: .light))
                Text(L10n.text("ここにドロップして取り込む")).font(.title3.weight(.semibold))
                Text(L10n.text("Windows のカーソルフォルダ、または theme.json のあるフォルダ"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Brand.accent)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Brand.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(8)
        )
        .allowsHitTesting(false)
    }
}

extension View {
    /// 内容の上に浮かぶもの(バナー)は、OS が対応していれば Liquid Glass、それ以前は素材と細い縁で描く。
    @ViewBuilder
    func glassOrMaterial(in shape: some InsettableShape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
    }
}

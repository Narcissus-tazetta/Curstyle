import AppKit
import CursorKit
import SwiftUI
import UniformTypeIdentifiers

/// カーソル1つのホットスポット・1コマの秒数・画像を編集する。保存するまでライブラリには書かない。
struct CursorEditorSheet: View {
    let model: AppModel
    let entry: ThemeLibrary.Entry
    let key: String

    @Environment(\.dismiss) private var dismiss
    @State private var rep: CursorRep
    @State private var appliesToSiblings = true
    @State private var imageSource: URL?
    @State private var pointSize: Double
    @State private var imageError: String?
    @State private var imageAdjustment: String?

    /// 同じ画像を共有しているキー(Windows の Horizontal は6つのサイズ変更に当たる、など)。
    private let siblings: [String]

    init(model: AppModel, entry: ThemeLibrary.Entry, key: String) {
        self.model = model
        self.entry = entry
        self.key = key
        let original = entry.theme.cursors[key]!
        _rep = State(initialValue: original)
        _pointSize = State(initialValue: max(original.size.width, original.size.height))
        let hash = original.contentHash
        siblings = entry.theme.cursors.filter { $0.key != key && $0.value.contentHash == hash }.map(\.key).sorted()
    }

    private var validationError: String? {
        do {
            try rep.validate()
            return nil
        } catch {
            return "\(error)"
        }
    }

    private var zoom: CGFloat { min(8, 240 / max(rep.size.width, rep.size.height)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(systemImage: "slider.horizontal.3", tint: .indigo, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("{0} を編集", String(describing: CursorRoles.title(for: key)))).font(
                        .title3.weight(.semibold))
                    Text("\(entry.theme.name) · \(key)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                canvas
                Form {
                    Section(L10n.text("ホットスポット(クリック位置)")) {
                        coordinateField("X", value: hotspotBinding(\.x), upper: rep.size.width)
                        coordinateField("Y", value: hotspotBinding(\.y), upper: rep.size.height)
                        Text(L10n.text("左のプレビューをクリック・ドラッグしても動かせます。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if rep.frameCount > 1 {
                        Section(L10n.text("アニメ")) {
                            HStack {
                                TextField(
                                    L10n.text("1コマの秒数"),
                                    value: Binding(
                                        get: { rep.frameDuration },
                                        set: { rep = rep.withFrameDuration($0) }),
                                    format: .number.precision(.fractionLength(0...3))
                                )
                                .frame(maxWidth: 180)
                                Stepper(
                                    "",
                                    value: Binding(
                                        get: { rep.frameDuration },
                                        set: { rep = rep.withFrameDuration(($0 * 100).rounded() / 100) }),
                                    in: 0.01...Double(Float.greatestFiniteMagnitude), step: 0.01
                                )
                                .labelsHidden()
                            }
                            Text(
                                String(
                                    format: L10n.text("%d コマ · 1周 %.2f 秒 · %.1f fps"), rep.frameCount,
                                    rep.frameDuration * Double(rep.frameCount), 1 / max(rep.frameDuration, 0.001))
                            )
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }
                    Section(L10n.text("画像")) {
                        HStack {
                            Button(L10n.text("GIF / PNG から差し替え…"), action: chooseImage)
                            if imageSource != nil {
                                Text(imageSource!.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        if imageSource != nil {
                            HStack {
                                TextField(L10n.text("大きさ (pt)"), value: $pointSize, format: .number)
                                    .frame(maxWidth: 180)
                                Stepper("", value: $pointSize, in: 8...128, step: 2).labelsHidden()
                            }
                            .onChange(of: pointSize) { loadImage() }
                            if !(8...128).contains(pointSize) {
                                Text(L10n.text("大きさは 8〜128 pt で指定してください"))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(
                            "\(Int(rep.size.width))×\(Int(rep.size.height)) pt\(rep.frameCount > 1 ? L10n.text(" · {0} コマ", String(describing: rep.frameCount)) : "")"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        if let imageAdjustment {
                            Label(imageAdjustment, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let imageError {
                            Label(imageError, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !siblings.isEmpty {
                        Section {
                            Toggle(isOn: $appliesToSiblings) {
                                Text(L10n.text("同じ画像を使う {0} 件にも反映", String(describing: siblings.count)))
                                Text(siblings.map(CursorRoles.title(for:)).joined(separator: "、"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(width: 340, height: 440)
            }

            HStack {
                if let validationError {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                Spacer()
                Button(L10n.text("キャンセル"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text("保存")) {
                    var theme = entry.theme
                    theme.cursors[key] = rep
                    if appliesToSiblings {
                        for sibling in siblings { theme.cursors[sibling] = rep }
                    }
                    if model.update(entry, with: theme) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    validationError != nil || imageError != nil
                        || (imageSource != nil && !(8...128).contains(pointSize)))
            }
        }
        .padding(20)
        .frame(width: 680)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    imageSource = url
                    loadImage()
                }
            }
            return true
        }
    }

    private var canvas: some View {
        let zoom = zoom
        let size = CGSize(width: rep.size.width * zoom, height: rep.size.height * zoom)
        return ZStack {
            BackdropView(backdrop: model.backdrop, cornerRadius: 12)
            CursorPreview(rep: rep, zoom: zoom, showsHotspot: true)
                .overlay(
                    Rectangle().strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3]))
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        // 0.5pt 刻み(Retina の1画素)にそろえる。
                        func snap(_ v: CGFloat, _ upper: CGFloat) -> CGFloat {
                            min(max((v / zoom * 2).rounded() / 2, 0), upper)
                        }
                        rep = rep.withHotspot(
                            CGPoint(
                                x: snap(value.location.x, rep.size.width), y: snap(value.location.y, rep.size.height)))
                    }
                )
                .frame(width: size.width, height: size.height)
        }
        .frame(width: 280, height: 280)
    }

    private func hotspotBinding(_ path: WritableKeyPath<CGPoint, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(rep.hotspot[keyPath: path]) },
            set: {
                var point = rep.hotspot
                point[keyPath: path] = CGFloat($0)
                rep = rep.withHotspot(point)
            })
    }

    private func coordinateField(_ label: String, value: Binding<Double>, upper: CGFloat) -> some View {
        HStack {
            TextField(label, value: value, format: .number.precision(.fractionLength(0...1)))
                .frame(maxWidth: 180)
            Stepper("", value: value, in: 0...Double(upper), step: 0.5).labelsHidden()
            Text("/ \(Int(upper)) pt").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.gif, .png]
        panel.allowsMultipleSelection = false
        panel.message = L10n.text("カーソルにする GIF(アニメ可)か PNG を選んでください")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        imageSource = url
        loadImage()
    }

    /// 差し替え前のホットスポットは、大きさの比で新しい画像に移す(左上の (0,0) に飛ばさない)。
    /// 大きさの欄は1文字ごとに値が変わる(「32」は 3 → 32)。途中の小さな値で作り直すとホットスポットが
    /// 丸めで崩れるので、範囲外の値では作り直さない。
    private func loadImage() {
        guard let imageSource, (8...128).contains(pointSize) else { return }
        do {
            let imported = try CursorRep.fromImageFile(imageSource, pointSize: pointSize)
            var made = imported.rep
            let ratio = max(made.size.width, made.size.height) / max(rep.size.width, rep.size.height)
            made.hotspot = CGPoint(
                x: min((rep.hotspot.x * ratio * 2).rounded() / 2, made.size.width),
                y: min((rep.hotspot.y * ratio * 2).rounded() / 2, made.size.height))
            rep = made
            imageAdjustment = imported.adjustment
            imageError = nil
        } catch {
            imageAdjustment = nil
            imageError = "\(error)"
        }
    }
}

/// テーマ全体のアニメの速さを一括で変える。
struct AnimationSpeedSheet: View {
    let model: AppModel
    let entry: ThemeLibrary.Entry

    @Environment(\.dismiss) private var dismiss
    @State private var factor = 1.0

    private var animatedKeys: [String] {
        entry.theme.cursors.filter { $0.value.frameCount > 1 }.map(\.key).sorted()
    }

    private var scaled: CursorTheme { entry.theme.scalingAnimationSpeed(by: factor) }

    private var validationError: String? {
        do {
            _ = try scaled.resolvedPlan()
            return nil
        } catch {
            return "\(error)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(systemImage: "speedometer", tint: .purple, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("アニメの速さを一括で変える")).font(.title3.weight(.semibold))
                    Text(L10n.text("{0} 件のアニメに同じ倍率をかけます", String(describing: animatedKeys.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                ForEach(animatedKeys.prefix(4), id: \.self) { key in
                    let rep = scaled.cursors[key]!
                    VStack(spacing: 4) {
                        ZStack {
                            BackdropView(backdrop: model.backdrop, cornerRadius: 8)
                            CursorPreview(rep: rep, zoom: min(2, 56 / max(rep.size.width, rep.size.height)))
                        }
                        .frame(width: 84, height: 72)
                        Text(String(format: L10n.text("%.3f 秒"), rep.frameDuration))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Slider(value: $factor, in: 0.5...2, step: 0.1) {
                    Text(L10n.text("速さ"))
                } minimumValueLabel: {
                    Text("0.5×")
                } maximumValueLabel: {
                    Text("2×")
                }
                Text(String(format: L10n.text("%.1f 倍"), factor))
                    .font(.callout.monospacedDigit().weight(.medium))
            }
            HStack {
                if let validationError {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                Spacer()
                Button(L10n.text("キャンセル"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text("保存")) {
                    if model.update(entry, with: scaled) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(validationError != nil || abs(factor - 1) < 0.01)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

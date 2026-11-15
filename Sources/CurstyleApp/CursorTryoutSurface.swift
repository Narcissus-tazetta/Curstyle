import AppKit
import CursorKit
import SwiftUI

// MARK: 領域

struct TryoutRegion: Equatable {
    let role: TryoutRole
    let isTarget: Bool
    let rect: CGRect
}

private struct TryoutRegionKey: PreferenceKey {
    static let defaultValue: [TryoutRegion] = []
    static func reduce(value: inout [TryoutRegion], nextValue: () -> [TryoutRegion]) {
        value += nextValue()
    }
}

private let tryoutSpace = "tryout"

extension View {
    /// この View の範囲を、試用エリアでの役割(カーソルの種類)と結びつける。
    func tryoutRegion(_ role: TryoutRole, isTarget: Bool = false) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TryoutRegionKey.self,
                    value: [TryoutRegion(role: role, isTarget: isTarget, rect: proxy.frame(in: .named(tryoutSpace)))])
            })
    }
}

// MARK: ポインター追跡

/// 試用エリアの中のポインターを追う。システムのカーソルは透明にして、プレビューを重ねて描く。
/// 透明カーソルはカーソル矩形・tracking area の仕組みで出入りに従って AppKit が戻すので、
/// 隠す/戻すの対を自前で管理しない(領域退出・ウィンドウ非アクティブ化・シートの破棄でも残らない)。
struct PointerTracker: NSViewRepresentable {
    var cursorAt: (CGPoint) -> NSCursor
    var onMove: (CGPoint?) -> Void
    var onClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        update(view)
        return view
    }

    func updateNSView(_ view: TrackerView, context: Context) { update(view) }

    private func update(_ view: TrackerView) {
        view.cursorAt = cursorAt
        view.onMove = onMove
        view.onClick = onClick
    }

    static let blankCursor: NSCursor = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }
        return NSCursor(image: image, hotSpot: .zero)
    }()

    final class TrackerView: NSView {
        var cursorAt: (CGPoint) -> NSCursor = { _ in .arrow }
        var onMove: (CGPoint?) -> Void = { _ in }
        var onClick: (CGPoint) -> Void = { _ in }
        private var isInside = false
        private var observers: [NSObjectProtocol] = []

        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                    owner: self))
        }

        private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

        private func track(_ event: NSEvent) {
            let p = point(event)
            isInside = true
            cursorAt(p).set()
            onMove(p)
        }

        override func mouseEntered(with event: NSEvent) { track(event) }
        override func mouseMoved(with event: NSEvent) { track(event) }
        override func mouseDragged(with event: NSEvent) { track(event) }
        override func cursorUpdate(with event: NSEvent) { track(event) }

        override func mouseExited(with event: NSEvent) { leave() }

        override func mouseDown(with event: NSEvent) {
            let p = point(event)
            onClick(p)
            track(event)
        }

        private func leave() {
            guard isInside else { return }
            isInside = false
            onMove(nil)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            // 非アクティブ化・最小化では mouseExited が来ないことがあるので、描いたプレビューを消す。
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                        [weak self] _ in
                        MainActor.assumeIsolated { self?.leave() }
                    })
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            // シートが閉じてもポインターが領域内に残っていると、透明カーソルのまま次の移動まで残る。
            if newWindow == nil, isInside {
                isInside = false
                NSCursor.arrow.set()
            }
            super.viewWillMove(toWindow: newWindow)
        }
    }
}

// MARK: 試用エリア

private struct Click: Equatable {
    let id = UUID()
    let point: CGPoint
    let hitTarget: Bool
}

/// サンプルページの上でカーソルを動かし、クリックして位置を確かめる。システムのカーソルは変更しない。
struct TryoutSurface: View {
    let reps: [TryoutRole: CursorRep]
    let dark: Bool

    @State private var pointer: CGPoint?
    @State private var regions: [TryoutRegion] = []
    @State private var click: Click?

    /// 倍率を動かしている間に下のスライダーが動かないよう、高さは固定にする(大きなカーソルは端で切れる)。
    private let height: CGFloat = 280

    private func role(at point: CGPoint) -> TryoutRole {
        regions.last { $0.rect.contains(point) }?.role ?? .arrow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                TryoutSamplePage(dark: dark)
                PointerTracker(
                    cursorAt: { point in
                        let role = role(at: point)
                        return reps[role] == nil ? systemCursor(role) : PointerTracker.blankCursor
                    },
                    onMove: { pointer = $0 },
                    onClick: { point in
                        let hit = regions.contains { $0.isTarget && $0.rect.contains(point) }
                        click = Click(point: point, hitTarget: hit)
                    })
                if let click {
                    ClickMarker(hit: click.hitTarget)
                        .offset(x: click.point.x - 12, y: click.point.y - 12)
                        .id(click.id)
                        .allowsHitTesting(false)
                }
                if let pointer, let rep = reps[role(at: pointer)] {
                    CursorPreview(rep: rep, zoom: 1)
                        .offset(x: pointer.x - rep.hotspot.x, y: pointer.y - rep.hotspot.y)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: tryoutSpace)
            .onPreferenceChange(TryoutRegionKey.self) { regions = $0 }
            .frame(height: height)
            // ポインターが外(スライダーなど)にあるときも、いまの大きさが実寸で分かるよう置いておく。
            .overlay(alignment: .bottomLeading) {
                if pointer == nil, let role = TryoutRole.allCases.first(where: { reps[$0] != nil }),
                    let rep = reps[role]
                {
                    HStack(alignment: .center, spacing: 10) {
                        CursorPreview(rep: rep, zoom: 1)
                        Text(
                            L10n.text(
                                "{0}: {1}×{2} pt", role.title, String(Int(rep.size.width)),
                                String(Int(rep.size.height)))
                        )
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(dark ? Color(white: 0.8) : Color(white: 0.3))
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 16)
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.text("試用エリア"))
            .accessibilityHint(L10n.text("マウスでカーソルの見え方とクリック位置を確かめます"))

            Text(caption)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
        }
    }

    private var caption: String {
        guard let click else { return L10n.text("エリア内をクリックすると、クリックした位置を確かめられます") }
        let x = String(format: "%.1f", click.point.x)
        let y = String(format: "%.1f", click.point.y)
        return click.hitTarget
            ? L10n.text("クリック位置 ({0}, {1}) pt: 的に命中", x, y)
            : L10n.text("クリック位置 ({0}, {1}) pt: 的から外れました", x, y)
    }

    private func systemCursor(_ role: TryoutRole) -> NSCursor {
        switch role {
        case .arrow: .arrow
        case .ibeam: .iBeam
        case .pointingHand: .pointingHand
        }
    }
}

private struct ClickMarker: View {
    let hit: Bool
    @State private var visible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tint = hit ? Color.green : Color.red
        ZStack {
            Circle().strokeBorder(tint, lineWidth: 2)
            Rectangle().fill(tint).frame(width: 1.5, height: 10)
            Rectangle().fill(tint).frame(width: 10, height: 1.5)
        }
        .frame(width: 24, height: 24)
        .opacity(visible ? 1 : 0)
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(reduceMotion ? nil : Motion.quick) { visible = false }
        }
    }
}

// MARK: サンプルページ

/// 明るさはアプリの外観と独立。文字・リンク・ボタンの色も背景ごとに決めて、どちらでも読める。
private struct TryoutSamplePage: View, Equatable {
    let dark: Bool

    var body: some View {
        let ink = dark ? Color(white: 0.94) : Color(white: 0.1)
        let secondary = dark ? Color(white: 0.7) : Color(white: 0.38)
        let link = dark ? Color(red: 0.45, green: 0.72, blue: 1) : Color(red: 0, green: 0.36, blue: 0.86)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(dark ? Color(white: 0.13) : Color(white: 0.97))
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("サンプルページ"))
                    .font(.headline)
                    .foregroundStyle(ink)
                Text(L10n.text("文字の上ではテキスト用のカーソルになります。\nThe quick brown fox jumps over the lazy dog. 0123456789"))
                    .font(.callout)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .tryoutRegion(.ibeam)
                HStack(alignment: .center, spacing: 16) {
                    Text(L10n.text("ドキュメントを見る"))
                        .font(.callout)
                        .underline()
                        .foregroundStyle(link)
                        .tryoutRegion(.pointingHand)
                    Text(L10n.text("ボタン"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(dark ? Color(white: 0.08) : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(link, in: Capsule())
                        .tryoutRegion(.pointingHand)
                    Spacer(minLength: 0)
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().fill(Color.red.opacity(0.25))
                            Circle().fill(Color.red.opacity(0.5)).padding(10)
                            Circle().fill(Color.red).padding(20)
                        }
                        .frame(width: 60, height: 60)
                        .tryoutRegion(.arrow, isTarget: true)
                        Text(L10n.text("的"))
                            .font(.caption)
                            .foregroundStyle(secondary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

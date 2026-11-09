import AppKit
import QuartzCore

/// 本物のカーソルを隠し、ディスプレイごとの透明ウィンドウにテーマの画像を描いてマウスに追従させる。
/// 本物を隠せない場面(Mission Control・Command+Shift+4・Dock の上など)では自前を透明にして本物に任せ、
/// 二重表示にしない(yield)。プロセスが終了すれば WindowServer が本物を表示に戻す(docs/PHASE3_5.md)。
/// main スレッドから使う前提。
@MainActor
public final class OverlayRenderer {
    public struct Status: Sendable {
        public var yieldCount = 0
        /// yield したときの最前面アプリ → 回数(どの場面で隠せなかったかの手がかり)
        public var yieldScenes: [String: Int] = [:]
        public var lastYieldAt: Date?
        public var unknownShapes: Set<String> = []
        public var yielding = false
    }

    let symbols: OverlaySymbols
    let matcher: ShapeMatcher
    /// 登録名 → テーマの内容
    let plan: [String: CursorRep]
    let log: (String) -> Void
    public var onStatusChange: (() -> Void)?
    public private(set) var status = Status()

    private let cid: Int32
    private var hideCount = 0
    private var lastRehide = 0.0
    private var windows: [NSWindow] = []
    private var layers: [CALayer] = []
    private var running = false
    private var link: CADisplayLink?
    private var idleTimer: Timer?
    private var stillFrames = 0
    private var idleTicks = 0
    private var activationObserver: NSObjectProtocol?
    private var lastSeed: Int32 = -1
    private var current: (size: CGSize, hotspot: CGPoint, frames: [CGImage], duration: Double)?
    private var cursorScale: CGFloat = 1
    private var location = CGPoint.zero
    private var trailing: DispatchWorkItem?

    public init(
        symbols: OverlaySymbols, matcher: ShapeMatcher, plan: [String: CursorRep], log: @escaping (String) -> Void
    ) {
        self.symbols = symbols
        self.matcher = matcher
        self.plan = plan
        self.log = log
        cid = symbols.mainConnection()
    }

    public func start() {
        let err = symbols.setProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        if err != 0 { log("SetsCursorInBackground が err=\(err) を返した") }
        hide()
        cursorScale = symbols.cursorScale(cid)
        location = NSEvent.mouseLocation
        rebuildWindows()
        startTracking()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.appActivated() }
        }
        log(
            "overlay 開始: 本物の表示=\(symbols.isCursorVisible) 照合表 \(matcher.count) 件 テーマ \(plan.count) 件 拡大率 \(cursorScale)"
        )
    }

    /// 本物を表示に戻せたかを返す。戻せなければ呼び出し側はプロセスを終了して WindowServer に戻させる。
    @discardableResult
    public func stop() -> Bool {
        stopTracking()
        trailing?.cancel()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        for w in windows { w.orderOut(nil) }
        windows = []
        layers = []
        // CGSHideCursor は呼んだ回数だけ数える(隠し直しのたびに増える)ので、同じ回数だけ表示する。
        for _ in 0..<hideCount { _ = symbols.showCursor(cid) }
        hideCount = 0
        // 表示の反映が少し遅れることがあるので、最大 0.5 秒待ってから判定する。
        var visible = symbols.isCursorVisible
        let deadline = Date().addingTimeInterval(0.5)
        while !visible, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            visible = symbols.isCursorVisible
        }
        log("overlay 停止: 本物の表示=\(visible)")
        return visible
    }

    /// ディスプレイの増減・配置の変更のたびに作り直す。
    public func rebuildWindows() {
        link?.invalidate()
        link = nil
        for w in windows { w.orderOut(nil) }
        windows = []
        layers = []
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)))
        for screen in NSScreen.screens {
            let w = NSPanel(
                contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = level
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.setFrame(screen.frame, display: false)
            w.contentView?.wantsLayer = true
            let layer = CALayer()
            layer.contentsScale = screen.backingScaleFactor
            layer.contentsGravity = .resize
            w.contentView!.layer!.addSublayer(layer)
            w.alphaValue = status.yielding ? 0 : 1
            w.orderFrontRegardless()
            windows.append(w)
            layers.append(layer)
        }
        lastSeed = -1
        refreshShape()
        move()
        if running { startLink() }
    }

    /// ポインターのサイズ設定が変わったとき。
    public func updateScale() {
        let old = cursorScale
        cursorScale = symbols.cursorScale(cid)
        if old != cursorScale { log("ポインターの拡大率 \(old) → \(cursorScale)") }
        lastSeed = -1
        refreshShape()
        move()
    }

    /// マウスの位置は NSEvent.mouseLocation を読んで取る。launchd から起動したヘルパーでは、許可なしだと
    /// グローバルモニタにも CGEventTap にもマウスイベントが届かない(実測)。動いている間は displayLink で
    /// 毎フレーム、止まっている間は idleInterval ごとに読む。止まっている間も形と本物の表示を確かめる。
    private func startTracking() {
        running = true
        startLink()
    }

    private func stopTracking() {
        running = false
        link?.invalidate()
        link = nil
        idleTimer?.invalidate()
        idleTimer = nil
    }

    static let idleInterval: TimeInterval = 1.0 / 15
    /// この回数のフレームで位置が変わらなければ間引きに移る(60Hz で約 0.5 秒)。
    static let framesBeforeIdle = 30

    private func startLink() {
        idleTimer?.invalidate()
        idleTimer = nil
        stillFrames = 0
        if let link {
            link.isPaused = false
            return
        }
        guard let view = windows.first?.contentView else { return }
        let l = view.displayLink(target: LinkTarget(self), selector: #selector(LinkTarget.tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func goIdle() {
        link?.isPaused = true
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.idleTick() }
        }
    }

    fileprivate func linkTick() {
        let p = NSEvent.mouseLocation
        if p != location {
            stillFrames = 0
            location = p
            mouseEvent()
        } else {
            stillFrames += 1
            if stillFrames >= Self.framesBeforeIdle { goIdle() }
        }
    }

    private func idleTick() {
        if NSEvent.mouseLocation != location {
            startLink()
            linkTick()
            return
        }
        reconcileVisibility()
        refreshShape()
        // ポインターのサイズは設定ファイルの変更通知でも拾うが、取りこぼしに備えて止まっている間に1秒ごとに確かめる。
        idleTicks += 1
        if idleTicks % 15 == 0 {
            let scale = symbols.cursorScale(cid)
            if scale != cursorScale { updateScale() }
        }
    }

    private func hide() {
        _ = symbols.hideCursor(cid)
        hideCount += 1
    }

    private func mouseEvent() {
        reconcileVisibility()
        refreshShape()
        move()
        scheduleTrailingChecks()
    }

    /// 下のアプリはマウスイベントを受けてから少し遅れてカーソルを設定する。最後のイベントの後に
    /// 何回か形を確かめ直す(マウスが止まっている間は何もしない)。
    private func scheduleTrailingChecks() {
        trailing?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.trailingCheck(remaining: Self.trailingDelays) }
        }
        trailing = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.trailingDelays[0], execute: item)
    }

    static let trailingDelays: [TimeInterval] = [0.05, 0.15, 0.4]

    private func trailingCheck(remaining: [TimeInterval]) {
        guard running else { return }
        reconcileVisibility()
        refreshShape()
        let rest = Array(remaining.dropFirst())
        guard let next = rest.first else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.trailingCheck(remaining: rest) }
        }
        trailing = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (next - remaining[0]), execute: item)
    }

    private func appActivated() {
        reconcileVisibility(force: true)
        // 切替先のアプリが通知より後で表示し直すことがある(Claude は +20/+50ms で実測)ので、1秒間だけ見張る。
        watchVisibility(until: ProcessInfo.processInfo.systemUptime + 1)
    }

    private func watchVisibility(until deadline: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                if self.symbols.isCursorVisible { self.reconcileVisibility(force: true) }
                if ProcessInfo.processInfo.systemUptime < deadline { self.watchVisibility(until: deadline) }
            }
        }
    }

    /// 本物が表示に戻っていたら隠し直す(100ms に1回まで。yield 中は1秒に1回)。隠し直しても表示のままなら自前を透明にする。
    private func reconcileVisibility(force: Bool = false) {
        if symbols.isCursorVisible {
            let now = ProcessInfo.processInfo.systemUptime
            // 隠せない場面(yield 中)は CGSHideCursor の回数が積み上がるだけなので、試す間隔を広げる。
            let interval = status.yielding ? 1.0 : 0.1
            if force || now - lastRehide > interval {
                lastRehide = now
                hide()
            }
        }
        let yield = symbols.isCursorVisible
        guard yield != status.yielding else { return }
        status.yielding = yield
        if yield {
            status.yieldCount += 1
            status.lastYieldAt = Date()
            let scene = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            status.yieldScenes[scene, default: 0] += 1
        }
        for w in windows { w.alphaValue = yield ? 0 : 1 }
        onStatusChange?()
    }

    private func refreshShape() {
        let seed = symbols.cursorSeed()
        guard seed != lastSeed else { return }
        lastSeed = seed
        guard let cursor = NSCursor.currentSystem else { return }
        let (name, key) = matcher.name(for: cursor)
        if let name, let rep = plan[name] {
            current = (rep.size, rep.hotspot, Self.frames(of: rep), rep.frameDuration)
        } else {
            if name == nil, status.unknownShapes.count < 200, status.unknownShapes.insert(key).inserted {
                onStatusChange?()
            }
            // テーマに無い形・照合できない形は、いま OS が出している画像をそのまま描く(= 標準の見た目)。
            guard let image = ShapeMatcher.largestImage(cursor.image) else { return }
            current = (cursor.image.size, cursor.hotSpot, [image], 0)
        }
        apply()
    }

    private func apply() {
        guard let current else { return }
        let size = CGSize(width: current.size.width * cursorScale, height: current.size.height * cursorScale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers {
            layer.removeAnimation(forKey: "frames")
            layer.contents = current.frames[0]
            layer.bounds = CGRect(origin: .zero, size: size)
            layer.anchorPoint = CGPoint(
                x: current.hotspot.x / current.size.width, y: 1 - current.hotspot.y / current.size.height)
            if current.frames.count > 1 {
                let anim = CAKeyframeAnimation(keyPath: "contents")
                anim.values = current.frames
                anim.calculationMode = .discrete
                anim.duration = current.duration * Double(current.frames.count)
                anim.repeatCount = .infinity
                anim.isRemovedOnCompletion = false
                layer.add(anim, forKey: "frames")
            }
        }
        CATransaction.commit()
    }

    private func move() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (w, layer) in zip(windows, layers) {
            let f = w.frame
            layer.isHidden = !f.insetBy(dx: -1, dy: -1).contains(location)
            layer.position = CGPoint(x: location.x - f.minX, y: location.y - f.minY)
        }
        CATransaction.commit()
    }

    /// 縦に並んだフレームを切り出す。最大解像度の画像を使い、layer の拡縮に任せる。
    static func frames(of rep: CursorRep) -> [CGImage] {
        guard let image = rep.images.max(by: { $0.width < $1.width }) else { return [] }
        guard rep.frameCount > 1 else { return [image] }
        let h = image.height / rep.frameCount
        return (0..<rep.frameCount).compactMap {
            image.cropping(to: CGRect(x: 0, y: $0 * h, width: image.width, height: h))
        }
    }
}

/// CADisplayLink はターゲットを強参照するので、循環参照にならないよう弱参照で中継する。
@MainActor
private final class LinkTarget: NSObject {
    weak var renderer: OverlayRenderer?
    init(_ renderer: OverlayRenderer) { self.renderer = renderer }
    @objc func tick() { renderer?.linkTick() }
}

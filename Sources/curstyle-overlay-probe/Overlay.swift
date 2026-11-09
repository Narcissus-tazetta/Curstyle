import AppKit
import Carbon
import QuartzCore

struct OverlayOptions {
    /// window: 小さいウィンドウを動かす / layer: 画面全体の透明ウィンドウの中で layer を動かす
    var mode = "layer"
    /// event: グローバルイベントモニタ / link: displayLink で毎フレーム位置を読む / tap: 受信専用 CGEventTap
    var source = "event"
    var hideReal = true
    /// 測定時に本物と見分けるため、自前カーソルを赤く染める
    var tint = true
    var excludeFromCapture = false
    var seconds = 20.0
    /// link のときだけ有効。速度から何ミリ秒先の位置に描くか(0 で予測しない)
    var predictMs = 0.0
    /// 自動判定用に、画面中央へ無地の灰色ウィンドウを出す(背景を固定するため)
    var pad = false
}

final class OverlayProbe: NSObject {
    let options: OverlayOptions
    let cid = mainConnection()
    var hideCount = 0
    var windows: [NSWindow] = []
    var cursorLayers: [CALayer] = []
    var smallWindow: NSWindow?
    var lastSeed: Int32 = -1
    var currentImage: NSImage?
    var currentHotspot = CGPoint.zero
    var currentShape = ""
    var latencies: [Double] = []
    var updates = 0
    var rehidesOnMouse = 0
    var unknownShapes: Set<String> = []
    var displayLink: CADisplayLink?
    var lastLinkLocation = CGPoint(x: -1, y: -1)
    var tap: CFMachPort?
    var lastLinkTime = 0.0
    var velocity = CGVector.zero
    var lastRehide = 0.0
    var yielding = false
    var padWindow: NSWindow?

    init(options: OverlayOptions) {
        self.options = options
    }

    func run() {
        let app = NSApplication.shared
        // .accessory だと CLI から起動したとき最前面になり、グローバルモニタにイベントが来なくなる(実測)
        app.setActivationPolicy(.prohibited)
        buildShapeTable()
        if options.hideReal {
            _ = sym("CGSSetConnectionProperty", SetPropFn.self)!(
                cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
            hide("start")
        }
        setUpWindows()
        if options.pad {
            let f = NSScreen.screens[0].frame
            let w = NSWindow(
                contentRect: NSRect(x: f.midX - 200, y: f.midY - 200, width: 400, height: 400),
                styleMask: [.borderless],
                backing: .buffered, defer: false)
            w.backgroundColor = NSColor(white: 0.5, alpha: 1)
            w.level = .floating
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.orderFrontRegardless()
            padWindow = w
        }
        refreshShape(force: true)
        moveTo(NSEvent.mouseLocation, eventTime: nil)
        startTracking()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification,
            object: nil)
        // 場面ごとの状態(本物の表示・自前ウィンドウが画面に載っているか・最前面・セキュア入力)を変化時だけ記録する
        var lastDiag = ""
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [self] _ in
            let ids = Set(windows.map { CGWindowID($0.windowNumber) })
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            let onscreen = info.filter { ids.contains(($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0) }
                .count
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil"
            let d =
                "diag real=\(cursorIsVisible() != 0 ? "VISIBLE" : "hidden") yielding=\(yielding) overlayOnscreen=\(onscreen)/\(ids.count) front=\(front) secureInput=\(IsSecureEventInputEnabled()) space=\(activeSpaceDescription())"
            if d != lastDiag {
                lastDiag = d
                log(d)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + options.seconds) { [self] in finish() }
        log("overlay start mode=\(options.mode) source=\(options.source) hideReal=\(options.hideReal) pid=\(getpid())")
        app.run()
    }

    func hide(_ reason: String) {
        _ = cgsHide(cid)
        hideCount += 1
        if reason != "mouse" { log("hide(\(reason)) count=\(hideCount) visible=\(cursorIsVisible() != 0)") }
    }

    func setUpWindows() {
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)))
        func configure(_ w: NSWindow) {
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = level
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            if options.excludeFromCapture { w.sharingType = .none }
            w.contentView?.wantsLayer = true
            w.orderFrontRegardless()
        }
        if options.mode == "window" {
            let w = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 64, height: 64), styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false)
            configure(w)
            let l = CALayer()
            w.contentView!.layer!.addSublayer(l)
            cursorLayers = [l]
            smallWindow = w
            windows = [w]
        } else {
            for screen in NSScreen.screens {
                let w = NSPanel(
                    contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                    defer: false)
                configure(w)
                w.setFrame(screen.frame, display: false)
                let l = CALayer()
                l.contentsScale = screen.backingScaleFactor
                w.contentView!.layer!.addSublayer(l)
                windows.append(w)
                cursorLayers.append(l)
            }
        }
    }

    func startTracking() {
        switch options.source {
        case "event":
            NSEvent.addGlobalMonitorForEvents(matching: [
                .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .leftMouseUp,
                .rightMouseDown, .rightMouseUp,
            ]) { [self] e in
                mouseEvent(location: NSEvent.mouseLocation, eventTime: e.timestamp)
            }
        case "link":
            let link = windows[0].contentView!.displayLink(target: self, selector: #selector(linkTick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        case "tap":
            let mask: CGEventMask =
                (1 << CGEventType.mouseMoved.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
                | (1 << CGEventType.rightMouseDragged.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.leftMouseUp.rawValue)
            let me = Unmanaged.passUnretained(self).toOpaque()
            guard
                let tap = CGEvent.tapCreate(
                    tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: mask,
                    callback: { _, _, event, refcon in
                        let probe = Unmanaged<OverlayProbe>.fromOpaque(refcon!).takeUnretainedValue()
                        let p = event.location
                        let h = NSScreen.screens[0].frame.height
                        let t = Double(event.timestamp) / 1e9
                        probe.mouseEvent(location: CGPoint(x: p.x, y: h - p.y), eventTime: t)
                        return Unmanaged.passUnretained(event)
                    }, userInfo: me)
            else {
                log("CGEvent.tapCreate failed (権限が要る可能性)")
                return
            }
            let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            self.tap = tap
        default:
            fatalError("unknown source \(options.source)")
        }
    }

    @objc func linkTick(_ link: CADisplayLink) {
        let p = NSEvent.mouseLocation
        let now = link.timestamp
        if options.predictMs > 0, lastLinkTime > 0, now > lastLinkTime {
            let dt = now - lastLinkTime
            let v = CGVector(dx: (p.x - lastLinkLocation.x) / dt, dy: (p.y - lastLinkLocation.y) / dt)
            // 1フレームの揺れで飛ばないよう軽く平滑化する。止まったら即 0 に戻す
            velocity =
                p == lastLinkLocation
                ? .zero : CGVector(dx: velocity.dx * 0.5 + v.dx * 0.5, dy: velocity.dy * 0.5 + v.dy * 0.5)
        }
        lastLinkTime = now
        let moved = p != lastLinkLocation
        lastLinkLocation = p
        let lead = options.predictMs / 1000
        let target = CGPoint(x: p.x + velocity.dx * lead, y: p.y + velocity.dy * lead)
        if moved || velocity != .zero || options.predictMs > 0 {
            mouseEvent(location: target, eventTime: nil)
        } else {
            reconcileVisibility()
            refreshShape(force: false)
        }
    }

    func mouseEvent(location: CGPoint, eventTime: TimeInterval?) {
        reconcileVisibility()
        refreshShape(force: false)
        moveTo(location, eventTime: eventTime)
    }

    /// 本物が表示に戻っていたら隠し直す。隠せない場面(Mission Control など)では自前を引っ込め、
    /// 二重表示にせず標準カーソルに任せる。隠し直しは 100ms に1回まで。
    func reconcileVisibility() {
        guard options.hideReal else { return }
        if cursorIsVisible() != 0 {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastRehide > 0.1 {
                lastRehide = now
                hide("mouse")
                rehidesOnMouse += 1
            }
        }
        let yield = cursorIsVisible() != 0
        if yield != yielding {
            yielding = yield
            log(yield ? "yield: 本物を隠せないので自前を引っ込める" : "resume: 自前に戻す")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for w in windows { w.alphaValue = yield ? 0 : 1 }
            CATransaction.commit()
        }
    }

    @objc func appActivated(_ note: Notification) {
        guard options.hideReal else { return }
        let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName ?? "?"
        log("activated \(app) visible=\(cursorIsVisible() != 0)")
        hide("activate")
        // 切替先のアプリが通知より後で表示し直すことがあるので、1秒間だけ見張る
        let start = Date()
        Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [self] t in
            if cursorIsVisible() != 0 {
                hide("activate+\(Int(Date().timeIntervalSince(start) * 1000))ms")
            }
            if Date().timeIntervalSince(start) > 1 { t.invalidate() }
        }
    }

    func refreshShape(force: Bool) {
        let seed = cursorSeed()
        guard force || seed != lastSeed else { return }
        lastSeed = seed
        guard let c = NSCursor.currentSystem else { return }
        let key = cursorKey(c)
        let shape = shapeTable[key]?.joined(separator: "|") ?? "UNKNOWN(\(key))"
        if shape.hasPrefix("UNKNOWN") && !unknownShapes.contains(key) {
            unknownShapes.insert(key)
            log("unknown shape key=\(key) size=\(c.image.size) hot=\(c.hotSpot)")
        }
        if shape != currentShape {
            currentShape = shape
            log("shape -> \(shape)")
        }
        currentHotspot = c.hotSpot
        currentImage = options.tint ? tinted(c.image) : c.image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in cursorLayers {
            l.contents = currentImage
            l.bounds = CGRect(origin: .zero, size: c.image.size)
            l.anchorPoint = CGPoint(x: c.hotSpot.x / c.image.size.width, y: 1 - c.hotSpot.y / c.image.size.height)
        }
        CATransaction.commit()
    }

    func moveTo(_ p: CGPoint, eventTime: TimeInterval?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let w = smallWindow {
            w.setFrameOrigin(CGPoint(x: p.x - 32, y: p.y - 32))
            cursorLayers[0].position = CGPoint(x: 32, y: 32)
        } else {
            for (w, l) in zip(windows, cursorLayers) {
                let f = w.frame
                l.isHidden = !f.insetBy(dx: -1, dy: -1).contains(p)
                l.position = CGPoint(x: p.x - f.minX, y: p.y - f.minY)
            }
        }
        CATransaction.commit()
        updates += 1
        if let t = eventTime {
            latencies.append((ProcessInfo.processInfo.systemUptime - t) * 1000)
        }
    }

    func tinted(_ image: NSImage) -> NSImage {
        let out = NSImage(size: image.size)
        for rep in image.representations {
            let px = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            guard
                let bmp = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(px.width), pixelsHigh: Int(px.height), bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                    bitsPerPixel: 0)
            else { continue }
            bmp.size = image.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)
            let r = NSRect(origin: .zero, size: image.size)
            rep.draw(in: r)
            // 自動判定(analyze)で数えやすいよう、形の中を純マゼンタで塗る
            NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1).set()
            r.fill(using: .sourceAtop)
            NSGraphicsContext.restoreGraphicsState()
            out.addRepresentation(bmp)
        }
        return out
    }

    func finish() {
        let sorted = latencies.sorted()
        func pct(_ q: Double) -> String {
            sorted.isEmpty ? "-" : String(format: "%.2f", sorted[min(sorted.count - 1, Int(Double(sorted.count) * q))])
        }
        log(
            "summary updates=\(updates) latency(event->moved, ms) n=\(sorted.count) p50=\(pct(0.5)) p90=\(pct(0.9)) p99=\(pct(0.99)) max=\(pct(1.0)) rehidesOnMouse=\(rehidesOnMouse) hideCount=\(hideCount) unknown=\(unknownShapes.count)"
        )
        exit(0)
    }
}

typealias SpaceFn = @convention(c) (Int32) -> UInt64
nonisolated(unsafe) let activeSpace = sym("CGSGetActiveSpace", SpaceFn.self)
func activeSpaceDescription() -> String {
    activeSpace.map { String($0(mainConnection())) } ?? "?"
}

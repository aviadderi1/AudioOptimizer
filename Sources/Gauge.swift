import AppKit

/// Round floating gauge that stays above every app and every Space.
final class GaugePanel: NSPanel {
    private let view: GaugeView
    var onClose: (() -> Void)?
    var onOpenMain: (() -> Void)?

    init(settings: Settings) {
        let size: CGFloat = 270
        var origin = NSPoint(x: 0, y: 0)
        if let x = Double(settings.get("gauge_x") ?? ""), let y = Double(settings.get("gauge_y") ?? "") {
            origin = NSPoint(x: x, y: y)
        } else if let vf = NSScreen.main?.visibleFrame {
            origin = NSPoint(x: vf.maxX - size - 24, y: vf.minY + 24)
        }
        view = GaugeView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        super.init(contentRect: NSRect(origin: origin, size: NSSize(width: size, height: size)),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        contentView = view
        view.closeAction = { [weak self] in self?.close() }
        view.openAction = { [weak self] in self?.onOpenMain?() }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { _ in
            settings.set("gauge_x", String(Double(self.frame.minX)))
            settings.set("gauge_y", String(Double(self.frame.minY)))
            settings.save()
        }
        LiveData.shared.onSample.append { [weak self] in self?.view.tick() }
    }

    override var canBecomeKey: Bool { return true }

    override func close() {
        super.close()
        onClose?()
    }
}

final class GaugeView: NSView {
    var closeAction: (() -> Void)?
    var openAction: (() -> Void)?
    private var appName = "—"
    private var appCPU: Double = 0
    private var busiest = ""
    private var lastTable = Date.distantPast
    private var srCPU: Double = -1
    private var spike: String?
    private var spikeUntil = Date.distantPast
    private var hoverClose = false
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { return true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    func tick() {
        let front = NSWorkspace.shared.frontmostApplication
        if let f = front, f.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            appName = f.localizedName ?? "—"
        }
        if Date().timeIntervalSince(lastTable) >= 2 {
            lastTable = Date()
            let pid = front?.processIdentifier
            DispatchQueue.global().async {
                let t = Apps.processTable()
                let top = t.values.filter { $0.name != "ADAudioOptimizer" && $0.name != "kernel_task" }.max { $0.cpu < $1.cpu }
                DispatchQueue.main.async {
                    if let p = pid, let row = t[p] { self.appCPU = row.cpu / Double(max(1, ProcessInfo.processInfo.activeProcessorCount)) }
                    if let sr = Apps.superRack().first, let row = t[sr.processIdentifier] { self.srCPU = row.cpu / Double(max(1, ProcessInfo.processInfo.activeProcessorCount)) } else { self.srCPU = -1 }
                    self.busiest = top.map { "\($0.name) \(Int($0.cpu.rounded()))%" } ?? ""
                }
            }
        }
        let d = LiveData.shared
        if !d.latencyPaused && d.lat > 500 {
            spike = "Spike \(Int(d.lat.rounded())) µs" + (busiest.isEmpty ? "" : " · " + busiest)
            spikeUntil = Date().addingTimeInterval(5)
        }
        needsDisplay = true
    }

    private var closeRect: NSRect {
        let r: CGFloat = 11
        return NSRect(x: bounds.midX - r, y: bounds.maxY - 22 - r, width: r * 2, height: r * 2)
    }

    override func updateTrackingAreas() {
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }

    override func mouseMoved(with event: NSEvent) {
        let h = closeRect.insetBy(dx: -3, dy: -3).contains(convert(event.locationInWindow, from: nil))
        if h != hoverClose { hoverClose = h; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) { hoverClose = false; needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if closeRect.insetBy(dx: -3, dy: -3).contains(p) { closeAction?() }
        else if event.clickCount == 2 { openAction?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        let m = NSMenu()
        m.addItem(withTitle: "Open AD Audio Optimizer", action: #selector(openMain), keyEquivalent: "").target = self
        m.addItem(withTitle: "Close gauge", action: #selector(closeGauge), keyEquivalent: "").target = self
        m.addItem(NSMenuItem.separator())
        m.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        NSMenu.popUpContextMenu(m, with: event, for: self)
    }

    @objc private func openMain() { openAction?() }
    @objc private func closeGauge() { closeAction?() }

    private func arc(_ r: CGFloat, _ w: CGFloat, _ from: CGFloat, _ sweep: CGFloat, _ c: NSColor) {
        guard sweep > 0.5 else { return }
        let p = NSBezierPath()
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        // flipped view: angles go clockwise
        p.appendArc(withCenter: center, radius: r, startAngle: from, endAngle: from + sweep, clockwise: false)
        p.lineWidth = w
        p.lineCapStyle = .round
        c.setStroke()
        p.stroke()
    }

    private func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ c: NSColor, _ y: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.font(size, weight), .foregroundColor: c]
        let sz = (s as NSString).size(withAttributes: attrs)
        (s as NSString).draw(at: NSPoint(x: bounds.midX - sz.width / 2, y: y - sz.height / 2), withAttributes: attrs)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        bounds.fill()
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        Theme.bg.withAlphaComponent(0.95).setFill()
        circle.fill()
        Theme.border.setStroke()
        circle.lineWidth = 1.5
        circle.stroke()

        let d = LiveData.shared
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let start: CGFloat = 135, sweep: CGFloat = 270

        let cores = d.cores
        for (i, v) in cores.enumerated() {
            let a = (Double(start) + Double(sweep) * (Double(i) + 0.5) / Double(cores.count)) * .pi / 180
            let r0: CGFloat = 115, r1 = r0 + CGFloat(max(3, v / 100 * 14))
            let p = NSBezierPath()
            p.move(to: NSPoint(x: c.x + CGFloat(cos(a)) * r0, y: c.y + CGFloat(sin(a)) * r0))
            p.line(to: NSPoint(x: c.x + CGFloat(cos(a)) * r1, y: c.y + CGFloat(sin(a)) * r1))
            p.lineWidth = max(2, min(5, 180 / CGFloat(max(1, cores.count))))
            p.lineCapStyle = .round
            (v > 85 ? Theme.bad : v > 60 ? Theme.warn : Theme.accent).setStroke()
            p.stroke()
        }

        arc(101, 9, start, sweep, Theme.track)
        arc(101, 9, start, sweep * CGFloat(min(1, d.cpu / 100)), d.cpu > 50 ? Theme.warn : Theme.accent)
        arc(87, 6, start, sweep, Theme.track)
        arc(87, 6, start, sweep * CGFloat(min(1, d.mem / 100)), d.mem > 90 ? Theme.warn : Theme.good)

        let paused = d.latencyPaused
        let lat = d.lat
        let lc = paused ? Theme.sub : lat > 1000 ? Theme.bad : lat > 500 ? Theme.warn : Theme.good
        text("LATENCY", 9, .regular, Theme.sub, 88)
        text(paused ? "—" : "\(Int(lat.rounded()))", 36, .semibold, lc, 122)
        text(paused ? "paused" : "µs", 11, .regular, lc, 150)

        let hist = Array(d.latHistory.suffix(60))
        if !paused && hist.count > 1 {
            let p = NSBezierPath()
            for (i, v) in hist.enumerated() {
                let pt = NSPoint(x: c.x - 52 + CGFloat(i) * (104 / 59), y: 180 - CGFloat(min(1, v / 1000)) * 20)
                if i == 0 { p.move(to: pt) } else { p.line(to: pt) }
            }
            p.lineWidth = 1.3
            lc.withAlphaComponent(0.8).setStroke()
            p.stroke()
        }

        if srCPU >= 0 {
            text("★ SuperRack · \(Int(srCPU.rounded()))%", 11, .semibold, NSColor(srgbRed: 245/255, green: 192/255, blue: 74/255, alpha: 1), 198)
        } else {
            let app = appName.count > 22 ? String(appName.prefix(21)) + "…" : appName
            text("\(app) · \(Int(appCPU.rounded()))%", 11, .regular, Theme.text, 198)
        }
        text("CPU \(Int(d.cpu.rounded()))%   MEM \(Int(d.mem.rounded()))%", 9.5, .regular, Theme.sub, 214)
        if let s = spike, Date() < spikeUntil {
            text(s.count > 30 ? String(s.prefix(29)) + "…" : s, 9.5, .semibold, Theme.bad, 229)
        }

        let cr = closeRect
        if hoverClose { Theme.card2.setFill(); NSBezierPath(ovalIn: cr).fill() }
        let m = cr.width * 0.32
        let x = NSBezierPath()
        x.move(to: NSPoint(x: cr.minX + m, y: cr.minY + m)); x.line(to: NSPoint(x: cr.maxX - m, y: cr.maxY - m))
        x.move(to: NSPoint(x: cr.maxX - m, y: cr.minY + m)); x.line(to: NSPoint(x: cr.minX + m, y: cr.maxY - m))
        x.lineWidth = 1.6
        x.lineCapStyle = .round
        (hoverClose ? Theme.text : Theme.sub).setStroke()
        x.stroke()
    }
}

/// 7-second start screen.
final class SplashWindow: NSWindow {
    private let wave = WaveView(frame: NSRect(x: 90, y: 270, width: 360, height: 40))
    private let msg = makeLabel("Loading…", size: 12, color: Theme.sub)
    private var timer: Timer?
    private let steps = ["Loading…", "Reading system info…", "Starting live monitor…", "Preparing deep scan…", "Almost ready…"]

    init(done: @escaping () -> Void) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 540, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 540, height: 400))
        root.fill = Theme.bg
        root.stroke = Theme.border
        root.corner = 14
        contentView = root
        let logo = LogoView(frame: NSRect(x: 210, y: 48, width: 120, height: 120))
        root.addSubview(logo)
        let t = makeLabel("AD Audio Optimizer", size: 26, weight: .semibold)
        t.alignment = .center
        t.frame = NSRect(x: 0, y: 184, width: 540, height: 34)
        root.addSubview(t)
        let s = makeLabel("AD SOUND & SERVICE", size: 12, color: Theme.sub)
        s.alignment = .center
        s.frame = NSRect(x: 0, y: 222, width: 540, height: 18)
        root.addSubview(s)
        root.addSubview(wave)
        msg.alignment = .center
        msg.frame = NSRect(x: 0, y: 322, width: 540, height: 18)
        root.addSubview(msg)
        center()
        let begin = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] tm in
            guard let self = self else { tm.invalidate(); return }
            let p = min(1, Date().timeIntervalSince(begin) / 7)
            self.wave.value = p
            self.msg.stringValue = self.steps[min(self.steps.count - 1, Int(p * Double(self.steps.count)))] + "  \(Int((p * 100).rounded()))%"
            if p >= 1 {
                tm.invalidate()
                self.wave.done = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.orderOut(nil); done() }
            }
        }
    }
}

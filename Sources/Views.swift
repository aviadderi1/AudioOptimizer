import AppKit

// MARK: - Logo

final class LogoView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let path = NSBezierPath(roundedRect: r, xRadius: r.width / 4, yRadius: r.width / 4)
        Theme.accent.setFill()
        path.fill()
        let wave = NSBezierPath()
        let w = r.width, h = r.height
        for i in 0...40 {
            let t = Double(i) / 40
            let x = w * 0.18 + w * 0.64 * CGFloat(t)
            let y = h / 2 + CGFloat(sin(t * .pi * 3) * Double(h) * 0.22 * sin(t * .pi))
            if i == 0 { wave.move(to: NSPoint(x: x, y: y)) } else { wave.line(to: NSPoint(x: x, y: y)) }
        }
        wave.lineWidth = max(2, w / 14)
        wave.lineCapStyle = .round
        wave.lineJoinStyle = .round
        NSColor.white.setStroke()
        wave.stroke()
    }
}

// MARK: - Waveform progress

final class WaveView: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }
    var done = false { didSet { needsDisplay = true } }
    private var amps: [CGFloat] = []

    private func build() {
        let n = max(10, Int(bounds.width / 5))
        var smooth = 0.5
        var seed: UInt64 = 7
        amps = (0..<n).map { i in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let rnd = Double(seed >> 33) / Double(1 << 31)
            let t = Double(i) / Double(n)
            let env = 0.35 + 0.65 * pow(sin(t * .pi), 0.7)
            let beat = 0.55 + 0.45 * abs(sin(Double(i) * 0.37) * cos(Double(i) * 0.11))
            smooth = smooth * 0.55 + rnd * 0.45
            return CGFloat(min(1, env * (0.45 * beat + 0.55 * smooth) * 1.25))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if amps.isEmpty || amps.count != max(10, Int(bounds.width / 5)) { build() }
        let n = amps.count
        let slot = bounds.width / CGFloat(n)
        let bw = max(2, slot * 0.6)
        let mid = bounds.height / 2
        for i in 0..<n {
            let t = (Double(i) + 0.5) / Double(n)
            let h = max(2, amps[i] * bounds.height * 0.92)
            let c: NSColor = t <= value ? (done ? Theme.good : (t > value - 0.035 ? Theme.accentLight : Theme.accent)) : Theme.track
            c.setFill()
            NSBezierPath(roundedRect: NSRect(x: CGFloat(i) * slot + (slot - bw) / 2, y: mid - h / 2, width: bw, height: h), xRadius: bw / 2, yRadius: bw / 2).fill()
        }
        if !done && value > 0 && value < 1 {
            Theme.text.setFill()
            NSRect(x: CGFloat(value) * bounds.width - 1, y: 0, width: 2, height: bounds.height).fill()
        }
    }
}

// MARK: - Status dot

enum DotState { case none, good, fix, bad, info, pending }

final class DotView: NSView {
    var state: DotState = .none { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let p = NSBezierPath(ovalIn: r)
        switch state {
        case .none: Theme.border.setStroke(); p.lineWidth = 1.4; p.stroke()
        case .pending: Theme.accent.setStroke(); p.lineWidth = 1.6; p.stroke()
        case .good: Theme.good.setFill(); p.fill()
        case .fix: Theme.warn.setFill(); p.fill()
        case .bad: Theme.bad.setFill(); p.fill()
        case .info: Theme.accent.setFill(); p.fill()
        }
    }

    static func describe(_ s: DotState) -> String {
        switch s {
        case .good: return "Already optimal on this Mac."
        case .fix: return "Can be improved. OPT will fix it."
        case .bad: return "Problem found."
        case .info: return "Information."
        default: return "Not checked yet. Run a deep scan."
        }
    }
}

// MARK: - Segmented bar (profiles and tabs)

final class SegmentedBar: NSView {
    private let titles: [String]
    private let symbols: [String?]
    private var rects: [NSRect] = []
    private var hover = -1
    var selected = 0 { didSet { needsDisplay = true } }
    var onChange: ((Int) -> Void)?
    var itemHeight: CGFloat = 32
    private var tracking: NSTrackingArea?

    init(titles: [String], symbols: [String?], itemHeight: CGFloat = 32) {
        self.titles = titles
        self.symbols = symbols
        self.itemHeight = itemHeight
        super.init(frame: .zero)
        layoutItems()
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { return true }

    private func layoutItems() {
        var x: CGFloat = 3
        rects = []
        for (i, t) in titles.enumerated() {
            let tw = (t as NSString).size(withAttributes: [.font: Theme.font(12.5)]).width
            let w = (symbols[i] == nil ? 16 + tw + 16 : 12 + 16 + 6 + tw + 12)
            rects.append(NSRect(x: x, y: 3, width: w, height: itemHeight))
            x += w + 3
        }
        setFrameSize(NSSize(width: x, height: itemHeight + 6))
    }

    override func updateTrackingAreas() {
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }

    override func draw(_ dirtyRect: NSRect) {
        let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        Theme.card.setFill(); outer.fill()
        Theme.border.setStroke(); outer.lineWidth = 1; outer.stroke()
        for (i, r) in rects.enumerated() {
            let on = i == selected, hv = i == hover && !on
            if on || hv {
                (on ? Theme.accent : Theme.card2).setFill()
                NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
            }
            let fg: NSColor = on ? .white : (hv ? Theme.text : Theme.sub)
            let attrs: [NSAttributedString.Key: Any] = [.font: Theme.font(12.5, on ? .medium : .regular), .foregroundColor: fg]
            let ts = (titles[i] as NSString).size(withAttributes: attrs)
            var tx = r.midX - ts.width / 2
            if let sym = symbols[i], let img = NSImage(systemSymbolName: sym, accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                let tinted = img.withSymbolConfiguration(cfg) ?? img
                let ir = NSRect(x: r.minX + 12, y: r.midY - 8, width: 16, height: 16)
                tinted.isTemplate = true
                NSGraphicsContext.saveGraphicsState()
                fg.set()
                let tintedImg = NSImage(size: ir.size, flipped: false) { rect in
                    tinted.draw(in: rect)
                    fg.set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                tintedImg.draw(in: ir)
                NSGraphicsContext.restoreGraphicsState()
                tx = ir.maxX + 6
            }
            (titles[i] as NSString).draw(at: NSPoint(x: tx, y: r.midY - ts.height / 2), withAttributes: attrs)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let h = rects.firstIndex { $0.contains(p) } ?? -1
        if h != hover { hover = h; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) { hover = -1; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = rects.firstIndex(where: { $0.contains(p) }), i != selected {
            selected = i
            onChange?(i)
        }
    }
}

// MARK: - Round LIVE OPT button

final class LiveButton: NSView {
    var active = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    private var pressed = false

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 2)
        let ring = NSBezierPath(ovalIn: r)
        ring.lineWidth = 2.5
        (active ? Theme.good : Theme.red).setStroke()
        ring.stroke()
        (pressed ? Theme.red.blended(withFraction: 0.25, of: .black)! : Theme.red).setFill()
        NSBezierPath(ovalIn: r.insetBy(dx: 5, dy: 5)).fill()
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.font(10.5, .bold), .foregroundColor: NSColor.white, .paragraphStyle: p]
        let s = active ? "LIVE\nON" : "LIVE\nOPT"
        let h = (s as NSString).boundingRect(with: NSSize(width: bounds.width, height: 100), options: .usesLineFragmentOrigin, attributes: attrs).height
        (s as NSString).draw(in: NSRect(x: 0, y: bounds.midY - h / 2, width: bounds.width, height: h), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) { pressed = true; needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false; needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

// MARK: - Live monitor strip (header, right side)

final class MonitorStrip: NSView {
    override var isFlipped: Bool { return true }
    private let labels = ["CPU", "Cores", "Memory", "Pressure", "Latency"]

    override func draw(_ dirtyRect: NSRect) {
        let d = LiveData.shared
        let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        Theme.card.setFill(); outer.fill()
        Theme.border.setStroke(); outer.stroke()
        let gap: CGFloat = 5, pad: CGFloat = 5
        let tw = (bounds.width - pad * 2 - gap * 4) / 5
        for i in 0..<5 {
            let r = NSRect(x: pad + CGFloat(i) * (tw + gap), y: pad, width: tw, height: bounds.height - pad * 2)
            Theme.tile.setFill()
            NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
            var value = ""
            var color = Theme.accent
            var warn = false
            switch i {
            case 0: value = "\(Int(d.cpu.rounded()))%"; warn = d.cpu > 50
            case 1: let m = d.cores.max() ?? 0; value = "\(Int(m.rounded()))%"; warn = m > 85
            case 2: value = "\(Int(d.mem.rounded()))%"; color = Theme.good; warn = d.mem > 90
            case 3: value = d.pressure >= 4 ? "high" : d.pressure >= 2 ? "warn" : "low"; color = Theme.good; warn = d.pressure >= 2
            default: value = d.latencyPaused ? "paused" : "\(Int(d.lat.rounded())) µs"; color = Theme.good; warn = !d.latencyPaused && d.lat > 500
            }
            (labels[i] as NSString).draw(at: NSPoint(x: r.minX + 6, y: r.minY + 3), withAttributes: [.font: Theme.font(10), .foregroundColor: Theme.sub])
            let vAttrs: [NSAttributedString.Key: Any] = [.font: Theme.font(10, .semibold), .foregroundColor: warn ? Theme.warn : Theme.text]
            let vs = (value as NSString).size(withAttributes: vAttrs)
            (value as NSString).draw(at: NSPoint(x: r.maxX - 6 - vs.width, y: r.minY + 3), withAttributes: vAttrs)
            let gr = NSRect(x: r.minX + 5, y: r.minY + 19, width: r.width - 10, height: r.height - 23)
            let lineColor = warn ? Theme.warn : color
            switch i {
            case 0: spark(gr, d.cpuHistory, 100, lineColor)
            case 1: coreBars(gr, d.cores)
            case 2: spark(gr, d.memHistory, 100, lineColor)
            case 3: spark(gr, d.memHistory, 100, lineColor.withAlphaComponent(0.6))
            default: if !d.latencyPaused { spark(gr, d.latHistory, max(1000, (d.latHistory.max() ?? 0) * 1.15), lineColor) }
            }
        }
    }

    private func spark(_ r: NSRect, _ values: [Double], _ maxV: Double, _ c: NSColor) {
        guard values.count > 1 else { return }
        let path = NSBezierPath()
        let n = values.count
        for (k, v) in values.enumerated() {
            let x = r.maxX - CGFloat(n - 1 - k) * (r.width / 119)
            let y = r.maxY - CGFloat(min(1, v / maxV)) * (r.height - 1)
            if k == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
        }
        let fill = path.copy() as! NSBezierPath
        fill.line(to: NSPoint(x: r.maxX, y: r.maxY))
        fill.line(to: NSPoint(x: r.maxX - CGFloat(n - 1) * (r.width / 119), y: r.maxY))
        fill.close()
        c.withAlphaComponent(0.2).setFill(); fill.fill()
        c.setStroke(); path.lineWidth = 1.3; path.stroke()
    }

    private func coreBars(_ r: NSRect, _ cores: [Double]) {
        guard !cores.isEmpty else { return }
        let slot = r.width / CGFloat(cores.count)
        for (i, v) in cores.enumerated() {
            let h = max(2, CGFloat(v / 100) * r.height)
            (v > 85 ? Theme.bad : v > 60 ? Theme.warn : Theme.accent).setFill()
            NSRect(x: r.minX + CGFloat(i) * slot, y: r.maxY - h, width: max(1.5, slot - 2), height: h).fill()
        }
    }
}

// MARK: - Scroll list (native overlay scrollers are already slim on macOS)

final class ListView: NSScrollView {
    let stack = FlippedView()
    private var y: CGFloat = 4

    init(frame: NSRect, color: NSColor = Theme.card) {
        super.init(frame: frame)
        drawsBackground = false
        hasVerticalScroller = true
        scrollerStyle = .overlay
        scrollerKnobStyle = .light
        autohidesScrollers = true
        stack.frame = NSRect(x: 0, y: 0, width: frame.width, height: 10)
        documentView = stack
    }

    required init?(coder: NSCoder) { fatalError() }

    var contentWidth: CGFloat { return frame.width - 14 }

    func clear() {
        stack.subviews.forEach { $0.removeFromSuperview() }
        y = 4
        stack.frame.size.height = 10
    }

    @discardableResult
    func addRow(_ view: NSView, height: CGFloat? = nil) -> NSView {
        let h = height ?? view.frame.height
        view.frame.origin = NSPoint(x: 0, y: y)
        stack.addSubview(view)
        y += h + 3
        stack.frame.size.height = max(y, frame.height)
        return view
    }

    func scrollToBottom() {
        let maxY = max(0, stack.frame.height - contentView.bounds.height)
        contentView.scroll(to: NSPoint(x: 0, y: maxY))
        reflectScrolledClipView(contentView)
    }

    func scrollToTop() {
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
    }
}

/// A row with a status dot and a label (findings, logs).
func dotRow(_ state: DotState, _ text: String, width: CGFloat, tip: String? = nil, color: NSColor? = nil) -> (FlippedView, DotView) {
    let label = wrapLabel(text, width: width - 18, size: 12, color: color ?? (state == .info ? Theme.sub : Theme.text))
    let h = max(18, label.frame.height)
    let row = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: h))
    let dot = DotView(frame: NSRect(x: 0, y: 5, width: 9, height: 9))
    dot.state = state
    label.frame.origin = NSPoint(x: 17, y: 0)
    row.addSubview(dot)
    row.addSubview(label)
    if let t = tip { row.toolTip = t; label.toolTip = t; dot.toolTip = t }
    return (row, dot)
}

/// Checkbox with light text for the dark theme.
func checkbox(_ title: String, checked: Bool, tip: String? = nil) -> NSButton {
    let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
    b.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: Theme.text, .font: Theme.font(12.5)])
    b.state = checked ? .on : .off
    b.toolTip = tip
    b.sizeToFit()
    return b
}

final class ActionButton: NSButton {
    var primary = false
    var onClick: (() -> Void)?

    convenience init(_ title: String, primary: Bool = false, action: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        self.primary = primary
        self.onClick = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = (primary ? Theme.accent : Theme.card2).cgColor
        layer?.borderColor = (primary ? Theme.accent : Theme.border).cgColor
        layer?.borderWidth = 1
        attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: primary ? NSColor.white : Theme.text, .font: Theme.font(primary ? 13.5 : 12.5, primary ? .semibold : .regular)])
        target = self
        self.action = #selector(fire)
        let w = (title as NSString).size(withAttributes: [.font: Theme.font(13.5)]).width + 34
        frame.size = NSSize(width: max(primary ? 120 : 100, w), height: 36)
    }

    @objc private func fire() { onClick?() }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.45 }
    }

    func setTitle(_ t: String) {
        attributedTitle = NSAttributedString(string: t, attributes: [.foregroundColor: primary ? NSColor.white : Theme.text, .font: Theme.font(primary ? 13.5 : 12.5, primary ? .semibold : .regular)])
    }
}

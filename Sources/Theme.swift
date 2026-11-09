import AppKit

enum Theme {
    static let bg = NSColor(srgbRed: 18/255, green: 20/255, blue: 25/255, alpha: 1)
    static let card = NSColor(srgbRed: 28/255, green: 31/255, blue: 38/255, alpha: 1)
    static let card2 = NSColor(srgbRed: 38/255, green: 42/255, blue: 51/255, alpha: 1)
    static let tile = NSColor(srgbRed: 24/255, green: 27/255, blue: 33/255, alpha: 1)
    static let border = NSColor(srgbRed: 52/255, green: 57/255, blue: 68/255, alpha: 1)
    static let text = NSColor(srgbRed: 232/255, green: 234/255, blue: 237/255, alpha: 1)
    static let sub = NSColor(srgbRed: 150/255, green: 158/255, blue: 170/255, alpha: 1)
    static let accent = NSColor(srgbRed: 59/255, green: 130/255, blue: 246/255, alpha: 1)
    static let accentLight = NSColor(srgbRed: 127/255, green: 176/255, blue: 255/255, alpha: 1)
    static let good = NSColor(srgbRed: 52/255, green: 211/255, blue: 120/255, alpha: 1)
    static let warn = NSColor(srgbRed: 245/255, green: 170/255, blue: 40/255, alpha: 1)
    static let bad = NSColor(srgbRed: 240/255, green: 80/255, blue: 80/255, alpha: 1)
    static let track = NSColor(srgbRed: 46/255, green: 52/255, blue: 64/255, alpha: 1)
    static let red = NSColor(srgbRed: 229/255, green: 72/255, blue: 77/255, alpha: 1)

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        return NSFont.systemFont(ofSize: size, weight: weight)
    }
}

/// Top-left origin view, like the Windows version.
class FlippedView: NSView {
    override var isFlipped: Bool { return true }
    var fill: NSColor? { didSet { needsDisplay = true } }
    var corner: CGFloat = 0
    var stroke: NSColor?

    override func draw(_ dirtyRect: NSRect) {
        guard let f = fill else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: corner, yRadius: corner)
        f.setFill()
        path.fill()
        if let s = stroke {
            s.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

func makeCard(_ frame: NSRect) -> FlippedView {
    let v = FlippedView(frame: frame)
    v.fill = Theme.card
    v.stroke = Theme.border
    v.corner = 9
    return v
}

func makeLabel(_ text: String, size: CGFloat = 12.5, weight: NSFont.Weight = .regular, color: NSColor = Theme.text) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = Theme.font(size, weight)
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    l.backgroundColor = .clear
    return l
}

func wrapLabel(_ text: String, width: CGFloat, size: CGFloat = 12.5, color: NSColor = Theme.text) -> NSTextField {
    let l = NSTextField(wrappingLabelWithString: text)
    l.font = Theme.font(size)
    l.textColor = color
    l.preferredMaxLayoutWidth = width
    l.frame.size = l.sizeThatFits(NSSize(width: width, height: 10000))
    l.frame.size.width = width
    return l
}

func formatBytes(_ b: Double) -> String {
    if b >= 1024 * 1024 * 1024 { return String(format: "%.1f GB", b / (1024 * 1024 * 1024)) }
    return String(format: "%.0f MB", b / (1024 * 1024))
}

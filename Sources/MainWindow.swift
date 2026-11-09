import AppKit

final class MainController: NSObject, NSWindowDelegate {
    let window: NSWindow
    let settings = Settings()
    let opt = Optimizer()
    var cats = Apps.categories()
    var gauge: GaugePanel?
    var onGaugeClosedWhileHidden: (() -> Void)?

    private let W: CGFloat = 1300, H: CGFloat = 820
    private let root = FlippedView()
    private var liveButton = LiveButton()
    private var profiles: SegmentedBar!
    private var profileDesc = makeLabel("", size: 11.5, color: Theme.sub)
    private let monitor = MonitorStrip()
    private var mScore = makeLabel("—", size: 22, weight: .semibold)
    private var mCPU = makeLabel("—", size: 22, weight: .semibold)
    private var mPressure = makeLabel("—", size: 22, weight: .semibold)
    private var mDevice = makeLabel("—", size: 13, weight: .semibold)
    private var mLat = makeLabel("—", size: 22, weight: .semibold)
    private var tabs: SegmentedBar!
    private var views: [NSView] = []
    private var status = makeLabel("", size: 12, color: Theme.sub)
    private var buttons: [ActionButton] = []
    private var busy = false
    private var loading = false

    // settings view
    private var boxes: [String: NSButton] = [:]
    private var dots: [String: DotView] = [:]
    private var appsList: ListView!

    // report view
    private let wave = WaveView(frame: .zero)
    private var waveStep = makeLabel("Ready", size: 12.5)
    private var waveCount = makeLabel("", size: 12, color: Theme.sub)
    private var wavePct = makeLabel("0%", size: 13, weight: .semibold, color: Theme.sub)
    private var stepsList: ListView!
    private var findList: ListView!
    private var findSummary = makeLabel("", size: 12, color: Theme.sub)
    private var stepDots: [DotView] = []

    // disk + audio views
    private var diskList: ListView!
    private var audioList: ListView!

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1300, height: 820), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "AD Audio Optimizer"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.bg
        window.isReleasedWhenClosed = false
        window.delegate = self
        root.frame = NSRect(x: 0, y: 0, width: W, height: H)
        root.fill = Theme.bg
        window.contentView = root
        build()
        loadSettings()
        window.center()
        opt.keepRuntime()
        LiveData.shared.onSample.append { [weak self] in self?.live() }
    }

    // MARK: layout

    private func build() {
        let top: CGFloat = 34 // below the traffic lights
        // header
        let logo = LogoView(frame: NSRect(x: 16, y: top + 6, width: 42, height: 42))
        root.addSubview(logo)
        let title = makeLabel("AD Audio Optimizer", size: 19, weight: .semibold)
        title.frame = NSRect(x: 68, y: top + 4, width: 220, height: 26)
        root.addSubview(title)
        let sub = makeLabel("AD SOUND & SERVICE", size: 11, color: Theme.sub)
        sub.frame = NSRect(x: 69, y: top + 30, width: 200, height: 16)
        root.addSubview(sub)

        liveButton.frame = NSRect(x: 276, y: top - 2, width: 60, height: 60)
        liveButton.toolTip = "Opens a round floating gauge that stays on top of every app: cores, CPU, memory, live latency and the app you're using. It keeps running even after you close this window."
        liveButton.onClick = { [weak self] in self?.toggleGauge() }
        root.addSubview(liveButton)

        profiles = SegmentedBar(titles: Catalog.profiles, symbols: ["mic", "slider.vertical.3", "speaker.wave.2", "gearshape"])
        profiles.frame.origin = NSPoint(x: 350, y: top)
        profiles.onChange = { [weak self] i in self?.applyProfile(i) }
        root.addSubview(profiles)
        profileDesc.frame = NSRect(x: 354, y: top + profiles.frame.height + 3, width: 420, height: 16)
        root.addSubview(profileDesc)

        let monX = profiles.frame.maxX + 16
        monitor.frame = NSRect(x: monX, y: top - 2, width: W - 16 - monX, height: 62)
        root.addSubview(monitor)

        // metrics
        let my = top + 70
        let mw = (W - 32 - 4 * 10) / 5
        let metrics: [(String, NSTextField, String)] = [
            ("Audio score", mScore, "How ready this Mac is for audio work, from 0 to 100."),
            ("CPU", mCPU, "Current total CPU load."),
            ("Memory pressure", mPressure, "How hard macOS is working to find free memory. Low is what you want."),
            ("Audio device", mDevice, "Default output device, sample rate and buffer size."),
            ("Latency", mLat, "Longest wake-up delay of a timer thread. Under 300 µs is great."),
        ]
        for (i, m) in metrics.enumerated() {
            let card = makeCard(NSRect(x: 16 + CGFloat(i) * (mw + 10), y: my, width: mw, height: 76))
            card.toolTip = m.2
            let cap = makeLabel(m.0, size: 11.5, color: Theme.sub)
            cap.frame = NSRect(x: 12, y: 9, width: mw - 24, height: 16)
            m.1.frame = NSRect(x: 12, y: 30, width: mw - 24, height: 32)
            card.addSubview(cap)
            card.addSubview(m.1)
            root.addSubview(card)
        }

        // tabs
        tabs = SegmentedBar(titles: ["Settings", "Scan report", "Disk health", "Audio device"], symbols: [nil, nil, nil, nil], itemHeight: 28)
        tabs.frame.origin = NSPoint(x: 16, y: my + 88)
        tabs.onChange = { [weak self] i in self?.showView(i) }
        root.addSubview(tabs)

        let cy = my + 88 + tabs.frame.height + 8
        let ch = H - cy - 66
        let content = NSRect(x: 16, y: cy, width: W - 32, height: ch)
        views = [buildSettings(content), buildReport(content), buildDisk(content), buildAudio(content)]
        for v in views { root.addSubview(v) }

        // bottom bar
        let by = H - 52
        var x: CGFloat = 16
        let defs: [(String, Bool, () -> Void)] = [
            ("⚡  OPT", true, { [weak self] in self?.doOptimize() }),
            ("Deep scan", false, { [weak self] in self?.runScan() }),
            ("Latency test", false, { [weak self] in self?.latencyTest() }),
            ("Restore defaults", false, { [weak self] in self?.doRestore() }),
        ]
        for d in defs {
            let b = ActionButton(d.0, primary: d.1, action: d.2)
            b.frame.origin = NSPoint(x: x, y: by)
            if d.1 { b.frame.size.width = 130 }
            root.addSubview(b)
            buttons.append(b)
            x += b.frame.width + 8
        }
        status.alignment = .right
        status.frame = NSRect(x: x + 10, y: by + 10, width: W - 16 - x - 10, height: 18)
        root.addSubview(status)
        showView(1)
    }

    private func sectionCard(_ frame: NSRect, _ title: String, _ tip: String) -> (FlippedView, ListView) {
        let card = makeCard(frame)
        let t = makeLabel(title + "  ⓘ", size: 13.5, weight: .semibold)
        t.frame = NSRect(x: 12, y: 9, width: frame.width - 24, height: 20)
        t.toolTip = tip
        card.addSubview(t)
        let list = ListView(frame: NSRect(x: 10, y: 36, width: frame.width - 16, height: frame.height - 44))
        card.addSubview(list)
        return (card, list)
    }

    private func settingRow(_ id: String, _ label: String, _ tip: String, width: CGFloat) -> FlippedView {
        let row = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        let dot = DotView(frame: NSRect(x: 2, y: 7, width: 9, height: 9))
        dot.toolTip = DotView.describe(.none)
        let cb = checkbox(label, checked: false, tip: tip)
        cb.frame.origin = NSPoint(x: 16, y: 1)
        cb.target = self
        cb.action = #selector(boxChanged(_:))
        cb.identifier = NSUserInterfaceItemIdentifier(id)
        row.addSubview(dot)
        row.addSubview(cb)
        dots[id] = dot
        boxes[id] = cb
        return row
    }

    @objc private func boxChanged(_ sender: NSButton) {
        guard !loading, let id = sender.identifier?.rawValue else { return }
        settings.set("box:" + id, sender.state == .on ? "1" : "0")
        if !id.hasPrefix("app:") && profiles.selected != 3 { profiles.selected = 3; profileDesc.stringValue = Catalog.profileDesc[3] }
    }

    private func buildSettings(_ r: NSRect) -> NSView {
        let v = FlippedView(frame: r)
        let cw = (r.width - 20) / 3, chh = (r.height - 10) / 2
        let apps = sectionCard(NSRect(x: 0, y: 0, width: cw, height: chh), "Apps to close",
                               "Closes background apps that use CPU, memory and disk while you record. Your DAW and audio apps are protected and never closed.")
        appsList = apps.1
        v.addSubview(apps.0)
        for (i, s) in Catalog.sections.enumerated() {
            let pos = i + 1
            let card = sectionCard(NSRect(x: CGFloat(pos % 3) * (cw + 10), y: CGFloat(pos / 3) * (chh + 10), width: cw, height: chh), s.title, s.tip)
            for item in s.items { card.1.addRow(settingRow(item.id, item.label, item.tip, width: card.1.contentWidth)) }
            v.addSubview(card.0)
        }
        // sixth slot: note about what macOS doesn't allow
        let note = makeCard(NSRect(x: 2 * (cw + 10), y: chh + 10, width: cw, height: chh))
        let nt = makeLabel("About the Mac version", size: 13.5, weight: .semibold)
        nt.frame = NSRect(x: 12, y: 9, width: cw - 24, height: 20)
        note.addSubview(nt)
        let body = wrapLabel("macOS manages CPU power, timers and USB power by itself, so the Windows-only tweaks (power plans, core parking, USB suspend, dynamic tick) don't exist here. Everything this app changes is undone by Restore defaults.", width: cw - 24, size: 12, color: Theme.sub)
        body.frame.origin = NSPoint(x: 12, y: 36)
        note.addSubview(body)
        v.addSubview(note)
        rebuildApps(daws: [])
        return v
    }

    private func buildReport(_ r: NSRect) -> NSView {
        let v = FlippedView(frame: r)
        let wc = makeCard(NSRect(x: 0, y: 0, width: r.width, height: 130))
        let t = makeLabel("Deep scan", size: 14, weight: .semibold)
        t.frame = NSRect(x: 16, y: 10, width: 200, height: 20)
        wc.addSubview(t)
        wavePct.alignment = .right
        wavePct.frame = NSRect(x: r.width - 116, y: 10, width: 100, height: 20)
        wc.addSubview(wavePct)
        wave.frame = NSRect(x: 16, y: 36, width: r.width - 32, height: 60)
        wc.addSubview(wave)
        waveStep.frame = NSRect(x: 16, y: 102, width: r.width - 200, height: 18)
        wc.addSubview(waveStep)
        waveCount.alignment = .right
        waveCount.frame = NSRect(x: r.width - 176, y: 102, width: 160, height: 18)
        wc.addSubview(waveCount)
        v.addSubview(wc)

        let lw = (r.width - 10) * 0.42, rw = r.width - 10 - lw, lh = r.height - 140
        let sc = makeCard(NSRect(x: 0, y: 140, width: lw, height: lh))
        let st = makeLabel("Scan steps", size: 13.5, weight: .semibold)
        st.frame = NSRect(x: 12, y: 9, width: 200, height: 20)
        sc.addSubview(st)
        stepsList = ListView(frame: NSRect(x: 10, y: 36, width: lw - 16, height: lh - 44))
        sc.addSubview(stepsList)
        for s in DeepScan.steps {
            let (row, dot) = dotRow(.none, s, width: stepsList.contentWidth, color: Theme.sub)
            stepsList.addRow(row)
            stepDots.append(dot)
        }
        v.addSubview(sc)

        let fc = makeCard(NSRect(x: lw + 10, y: 140, width: rw, height: lh))
        let ft = makeLabel("Findings", size: 13.5, weight: .semibold)
        ft.frame = NSRect(x: 12, y: 9, width: 200, height: 20)
        fc.addSubview(ft)
        findSummary.alignment = .right
        findSummary.frame = NSRect(x: rw - 260, y: 10, width: 246, height: 18)
        fc.addSubview(findSummary)
        findList = ListView(frame: NSRect(x: 10, y: 36, width: rw - 16, height: lh - 44))
        fc.addSubview(findList)
        v.addSubview(fc)
        return v
    }

    private func buildDisk(_ r: NSRect) -> NSView {
        let v = FlippedView(frame: r)
        let c = makeCard(NSRect(x: 0, y: 0, width: r.width, height: r.height))
        let t = makeLabel("Disk health", size: 14, weight: .semibold)
        t.frame = NSRect(x: 16, y: 10, width: 300, height: 20)
        c.addSubview(t)
        let verify = ActionButton("Verify startup disk", action: { [weak self] in self?.verifyDisk() })
        verify.frame.origin = NSPoint(x: r.width - verify.frame.width - 140, y: 8)
        verify.toolTip = "Runs diskutil verifyVolume on the startup disk (read-only check, asks for your password)."
        c.addSubview(verify)
        let du = ActionButton("Disk Utility", action: { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app")) })
        du.frame.origin = NSPoint(x: r.width - du.frame.width - 16, y: 8)
        c.addSubview(du)
        diskList = ListView(frame: NSRect(x: 14, y: 52, width: r.width - 24, height: r.height - 62))
        c.addSubview(diskList)
        v.addSubview(c)
        return v
    }

    private func buildAudio(_ r: NSRect) -> NSView {
        let v = FlippedView(frame: r)
        let c = makeCard(NSRect(x: 0, y: 0, width: r.width, height: r.height))
        let t = makeLabel("Audio devices", size: 14, weight: .semibold)
        t.frame = NSRect(x: 16, y: 10, width: 300, height: 20)
        c.addSubview(t)
        let refresh = ActionButton("Refresh", action: { [weak self] in self?.loadAudio() })
        refresh.frame.origin = NSPoint(x: r.width - refresh.frame.width - 150, y: 8)
        c.addSubview(refresh)
        let midi = ActionButton("Audio MIDI Setup", action: { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app")) })
        midi.frame.origin = NSPoint(x: r.width - midi.frame.width - 16, y: 8)
        c.addSubview(midi)
        audioList = ListView(frame: NSRect(x: 14, y: 52, width: r.width - 24, height: r.height - 62))
        c.addSubview(audioList)
        v.addSubview(c)
        return v
    }

    private var loaded = [false, false, false, false]

    private func showView(_ i: Int) {
        if tabs.selected != i { tabs.selected = i }
        for (k, v) in views.enumerated() { v.isHidden = k != i }
        if !loaded[i] {
            loaded[i] = true
            if i == 2 { loadDisks() }
            if i == 3 { loadAudio() }
        }
    }

    // MARK: settings

    private func loadSettings() {
        loading = true
        let p = Int(settings.get("profile") ?? "0") ?? 0
        profiles.selected = p
        profileDesc.stringValue = Catalog.profileDesc[min(3, max(0, p))]
        let defaults = Catalog.profileSet(p == 3 ? 0 : p)
        for (id, b) in boxes {
            if let s = settings.get("box:" + id) { b.state = s == "1" ? .on : .off } else { b.state = defaults.contains(id) ? .on : .off }
        }
        loading = false
    }

    private func saveSettings() {
        settings.set("profile", String(profiles.selected))
        for (id, b) in boxes { settings.set("box:" + id, b.state == .on ? "1" : "0") }
        settings.save()
    }

    private func applyProfile(_ i: Int) {
        profileDesc.stringValue = Catalog.profileDesc[i]
        if i == 3 { return }
        loading = true
        var set = Catalog.profileSet(i)
        if i == 0 { set.insert("wifi") }
        for (id, b) in boxes where !id.hasPrefix("app:") { b.state = set.contains(id) ? .on : .off }
        loading = false
        saveSettings()
    }

    private func rebuildApps(daws: [String]) {
        for k in boxes.keys where k.hasPrefix("app:") { boxes.removeValue(forKey: k); dots.removeValue(forKey: k) }
        appsList.clear()
        var any = false
        for c in cats where !c.found.isEmpty {
            any = true
            let row = settingRow("app:" + c.id, c.summary, c.tip, width: appsList.contentWidth)
            let saved = settings.get("box:app:" + c.id)
            boxes["app:" + c.id]?.state = (saved != nil ? saved == "1" : c.defaultOn) ? .on : .off
            dots["app:" + c.id]?.state = c.defaultOn ? .fix : .info
            appsList.addRow(row)
        }
        if !any { appsList.addRow(dotRow(.good, "No background apps to close", width: appsList.contentWidth).0) }
        for d in daws { appsList.addRow(dotRow(.none, "Protected · " + d, width: appsList.contentWidth, color: Theme.sub).0) }
    }

    // MARK: live

    private func live() {
        let d = LiveData.shared
        monitor.needsDisplay = true
        mCPU.stringValue = "\(Int(d.cpu.rounded()))%"
        mCPU.textColor = d.cpu > 40 ? Theme.bad : d.cpu > 15 ? Theme.warn : Theme.text
        mPressure.stringValue = d.pressure >= 4 ? "High" : d.pressure >= 2 ? "Warning" : "Low"
        mPressure.textColor = d.pressure >= 4 ? Theme.bad : d.pressure >= 2 ? Theme.warn : Theme.good
        if !d.latencyPaused && !d.latHistory.isEmpty {
            let l = d.lat
            mLat.stringValue = "\(Int(l.rounded())) µs"
            mLat.textColor = l < 300 ? Theme.good : l < 1000 ? Theme.warn : Theme.bad
        }
    }

    func refreshDevice() {
        if let id = Audio.defaultDevice(input: false) {
            let a = Audio.info(id)
            mDevice.stringValue = "\(a.name) · \(Int(a.sampleRate / 1000)) kHz · \(a.bufferFrames)"
            mDevice.toolTip = "\(a.name), \(Int(a.sampleRate)) Hz, buffer \(a.bufferFrames) frames, \(a.transport)"
        }
    }

    private func setBusy(_ b: Bool) {
        busy = b
        for btn in buttons { btn.isEnabled = !b }
    }

    private func setStatus(_ s: String, _ c: NSColor = Theme.sub) {
        DispatchQueue.main.async { self.status.stringValue = s; self.status.textColor = c }
    }

    // MARK: actions

    func runScan(then: (() -> Void)? = nil) {
        if busy { return }
        setBusy(true)
        showView(1)
        wave.done = false
        wave.value = 0
        wavePct.stringValue = "0%"
        waveStep.stringValue = "Starting…"
        findList.clear()
        findSummary.stringValue = ""
        for d in stepDots { d.state = .none }
        setStatus("Deep scan in progress…")
        let scan = DeepScan(cats: cats)
        let n = DeepScan.steps.count
        scan.stepStarted = { i in DispatchQueue.main.async {
            self.stepDots[i].state = .pending
            self.waveStep.stringValue = DeepScan.steps[i] + "…"
            self.waveCount.stringValue = "step \(i + 1) of \(n)"
        } }
        scan.stepDone = { i in DispatchQueue.main.async { self.stepDots[i].state = .good } }
        scan.progress = { p in DispatchQueue.main.async { self.wave.value = p; self.wavePct.stringValue = "\(Int((p * 100).rounded()))%" } }
        scan.found = { f in DispatchQueue.main.async { self.addFinding(f) } }
        DispatchQueue.global(qos: .userInitiated).async {
            let r = scan.run()
            DispatchQueue.main.async {
                self.applyScan(r)
                self.setBusy(false)
                then?()
            }
        }
    }

    private func addFinding(_ f: Finding) {
        let w = findList.contentWidth
        let (row, _) = dotRow(f.state, f.text, width: w - 60, tip: f.tip)
        row.frame.size.width = w
        if let sid = f.settingId, f.state == .fix || f.state == .bad {
            let fix = ActionButton("Fix →", action: { [weak self] in self?.jumpTo(sid) })
            fix.frame = NSRect(x: w - 56, y: 0, width: 52, height: 18)
            fix.layer?.backgroundColor = NSColor.clear.cgColor
            fix.layer?.borderWidth = 0
            fix.attributedTitle = NSAttributedString(string: "Fix →", attributes: [.foregroundColor: Theme.accent, .font: Theme.font(12, .medium)])
            row.addSubview(fix)
        }
        findList.addRow(row)
        findList.scrollToBottom()
    }

    private func jumpTo(_ id: String) {
        showView(0)
        if let b = boxes[id] { b.state = .on; settings.set("box:" + id, "1") }
    }

    private func applyScan(_ r: ScanResult) {
        rebuildApps(daws: r.daws)
        for (id, d) in dots {
            let s = r.states[id] ?? (id.hasPrefix("app:") ? d.state : .none)
            d.state = s
            d.toolTip = DotView.describe(s)
        }
        mScore.stringValue = "\(r.score)"
        mScore.textColor = r.score >= 85 ? Theme.good : r.score >= 60 ? Theme.warn : Theme.bad
        let l = r.latency.max
        mLat.stringValue = "\(Int(l.rounded())) µs"
        refreshDevice()
        wave.done = true
        wave.value = 1
        wavePct.stringValue = "100%"
        let summary = "\(r.problems) problem\(r.problems == 1 ? "" : "s") · \(r.warnings) to improve"
        waveStep.stringValue = "Scan complete · " + summary
        waveCount.stringValue = "\(DeepScan.steps.count) of \(DeepScan.steps.count)"
        findSummary.stringValue = summary
        findList.scrollToTop()
        setStatus(opt.backup.active ? "Optimized session active · press Restore defaults when you finish" : "Scanned · press OPT to fix what's checked", opt.backup.active ? Theme.good : Theme.sub)
    }

    private func doOptimize() {
        if busy { return }
        saveSettings()
        let sel = Set(boxes.filter { $0.value.state == .on }.map { $0.key })
        if sel.isEmpty { setStatus("Nothing is checked", Theme.warn); return }
        let closing = cats.filter { sel.contains("app:" + $0.id) && !$0.found.isEmpty }
        if !closing.isEmpty {
            let a = NSAlert()
            a.messageText = "These apps will be closed"
            a.informativeText = closing.map { "• " + $0.summary }.joined(separator: "\n") + "\n\nSave any open work in them first."
            a.addButton(withTitle: "Continue")
            a.addButton(withTitle: "Cancel")
            if a.runModal() != .alertFirstButtonReturn { return }
        }
        setBusy(true)
        DispatchQueue.global(qos: .userInitiated).async {
            let res = self.opt.apply(sel, cats: self.cats) { m in self.setStatus(m) }
            DispatchQueue.main.async {
                self.setBusy(false)
                self.showResults("OPT complete", res)
                self.runScan()
            }
        }
    }

    private func doRestore() {
        if busy { return }
        if !opt.backup.active { setStatus("Nothing to restore. This Mac is on its normal settings."); return }
        setBusy(true)
        DispatchQueue.global(qos: .userInitiated).async {
            let res = self.opt.restore { m in self.setStatus(m) }
            DispatchQueue.main.async {
                self.setBusy(false)
                self.showResults("Restore complete", res)
                self.runScan()
            }
        }
    }

    private func latencyTest() {
        if busy { return }
        setBusy(true)
        LiveData.shared.latencyPaused = true
        DispatchQueue.global(qos: .userInteractive).async {
            let r = LiveData.measure(seconds: 10) { p in self.setStatus("Measuring latency… \(Int((p * 100).rounded()))%  (don't use the Mac)") }
            DispatchQueue.main.async {
                LiveData.shared.latencyPaused = false
                self.setBusy(false)
                let us = r.max
                let v = us < 250 ? "great · 32–64 sample buffers" : us < 500 ? "good · 64–128 sample buffers" : us < 1000 ? "OK · 128–256 sample buffers" : "high · use 256–512 samples"
                self.mLat.stringValue = "\(Int(us.rounded())) µs"
                self.setStatus("Max \(Int(us.rounded())) µs · 99% under \(Int(r.p99.rounded())) µs · \(v)", us < 500 ? Theme.good : us < 1000 ? Theme.warn : Theme.bad)
            }
        }
    }

    private func showResults(_ title: String, _ lines: [String]) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = lines.isEmpty ? "Nothing to change." : lines.joined(separator: "\n")
        a.addButton(withTitle: "Close")
        a.runModal()
    }

    // MARK: disk + audio

    private func loadDisks() {
        diskList.clear()
        diskList.addRow(dotRow(.pending, "Reading disks…", width: diskList.contentWidth).0)
        DispatchQueue.global().async {
            let disks = Disks.list()
            let fs = Disks.freeSpace()
            DispatchQueue.main.async {
                self.diskList.clear()
                let w = self.diskList.contentWidth
                for d in disks {
                    let st: DotState = d.smart == "Verified" ? .good : d.smart == "Not Supported" ? .info : .bad
                    self.diskList.addRow(dotRow(st, "\(d.id) · \(d.name) · \(d.ssd ? "SSD" : "HDD") · \(d.bus) · \(formatBytes(d.size)) · \(d.isInternal ? "internal" : "external") · SMART: \(d.smart)", width: w,
                                               tip: st == .bad ? "The disk reports a problem. Back up now and run First Aid in Disk Utility." : nil).0)
                }
                let hours = fs.free / (16.0 * 48000 * 3 * 3600)
                self.diskList.addRow(dotRow(fs.free < 20e9 ? .bad : .good, "Startup disk: \(formatBytes(fs.free)) free of \(formatBytes(fs.total)) ≈ \(String(format: "%.1f", hours)) h of 16-track 48 kHz / 24-bit recording", width: w).0)
                self.diskList.addRow(dotRow(.info, "Mac SSDs manage bad blocks themselves, so a sector-by-sector scan isn't useful here. Use 'Verify startup disk' or First Aid in Disk Utility to check the file system.", width: w).0)
            }
        }
    }

    private func verifyDisk() {
        diskList.addRow(dotRow(.pending, "Verifying the startup disk (read-only)…", width: diskList.contentWidth).0)
        diskList.scrollToBottom()
        DispatchQueue.global().async {
            let (ok, out) = Shell.admin("/usr/sbin/diskutil verifyVolume /", timeout: 3600)
            let last = out.components(separatedBy: CharacterSet.newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.last ?? ""
            DispatchQueue.main.async {
                self.diskList.addRow(dotRow(ok ? .good : .fix, ok ? "Startup disk verified: " + last : "Verify didn't finish: " + (last.isEmpty ? "password not given" : last), width: self.diskList.contentWidth).0)
                self.diskList.scrollToBottom()
            }
        }
    }

    private func loadAudio() {
        audioList.clear()
        let w = audioList.contentWidth
        let outId = Audio.defaultDevice(input: false), inId = Audio.defaultDevice(input: true)
        for id in Audio.allDevices() {
            let d = Audio.info(id)
            let roles = [id == outId ? "default output" : nil, id == inId ? "default input" : nil].compactMap { $0 }.joined(separator: ", ")
            let row = FlippedView(frame: NSRect(x: 0, y: 0, width: w, height: 34))
            let (info, _) = dotRow(d.transport == "Bluetooth" ? .fix : (roles.isEmpty ? .none : .good),
                                   "\(d.name) · \(d.transport) · \(d.inputs) in / \(d.outputs) out · \(Int(d.sampleRate)) Hz · buffer \(d.bufferFrames)" + (roles.isEmpty ? "" : " · " + roles),
                                   width: w - 140, tip: d.transport == "Bluetooth" ? "Bluetooth audio adds a lot of delay. Don't record through it." : nil)
            info.frame.origin = NSPoint(x: 0, y: 7)
            row.addSubview(info)
            if d.rates.count > 1 {
                let pop = NSPopUpButton(frame: NSRect(x: w - 130, y: 4, width: 126, height: 24), pullsDown: false)
                for r in d.rates { pop.addItem(withTitle: "\(Int(r)) Hz") }
                pop.selectItem(withTitle: "\(Int(d.sampleRate)) Hz")
                pop.toolTip = "Change this device's sample rate"
                pop.target = self
                pop.action = #selector(rateChanged(_:))
                pop.tag = Int(id)
                row.addSubview(pop)
            }
            audioList.addRow(row)
        }
        refreshDevice()
    }

    @objc private func rateChanged(_ sender: NSPopUpButton) {
        guard let t = sender.titleOfSelectedItem, let r = Double(t.replacingOccurrences(of: " Hz", with: "")) else { return }
        let ok = Audio.setSampleRate(AudioDeviceID(sender.tag), r)
        setStatus(ok ? "Sample rate set to \(Int(r)) Hz" : "Couldn't change the sample rate", ok ? Theme.good : Theme.warn)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.loadAudio() }
    }

    // MARK: gauge and window

    func toggleGauge() {
        if let g = gauge { g.close(); return }
        let g = GaugePanel(settings: settings)
        g.onOpenMain = { [weak self] in self?.showMain() }
        g.onClose = { [weak self] in
            guard let self = self else { return }
            self.gauge = nil
            self.liveButton.active = false
            if !self.window.isVisible { self.onGaugeClosedWhileHidden?() }
        }
        g.orderFrontRegardless()
        gauge = g
        liveButton.active = true
    }

    func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        saveSettings()
        if gauge == nil { NSApp.terminate(nil); return false }
        window.orderOut(nil)
        return false
    }
}

import AppKit

struct Finding {
    let state: DotState
    let text: String
    var tip: String? = nil
    var settingId: String? = nil
}

final class ScanResult {
    var states: [String: DotState] = [:]
    var findings: [Finding] = []
    var daws: [String] = []
    var latency: (max: Double, p99: Double, avg: Double) = (0, 0, 0)
    var score = 0
    var problems: Int { return findings.filter { $0.state == .bad }.count }
    var warnings: Int { return findings.filter { $0.state == .fix }.count }
}

final class DeepScan {
    static let steps = [
        "System info: chip, memory, macOS",
        "Running apps and CPU/memory per app",
        "Background agents and login items",
        "Power: Low Power Mode, sleep, App Nap",
        "Background jobs: Spotlight, Time Machine",
        "Audio device: sample rate and buffer",
        "Memory pressure",
        "Disks: health and free space",
        "Network: Wi‑Fi and Bluetooth",
        "Latency test (8 s)",
    ]

    var stepStarted: (Int) -> Void = { _ in }
    var stepDone: (Int) -> Void = { _ in }
    var progress: (Double) -> Void = { _ in }
    var found: (Finding) -> Void = { _ in }

    private let cats: [AppCategory]
    private let res = ScanResult()

    init(cats: [AppCategory]) { self.cats = cats }

    private func add(_ s: DotState, _ text: String, tip: String? = nil, setting: String? = nil) {
        let f = Finding(state: s, text: text, tip: tip, settingId: setting)
        res.findings.append(f)
        found(f)
    }

    private func state(_ id: String, _ good: Bool) { res.states[id] = good ? .good : .fix }

    func run() -> ScanResult {
        let fns: [() -> Void] = [self.sysInfo, self.apps, self.agents, self.power, self.jobs, self.audio, self.memory, self.disks, self.network, self.latency]
        for (i, f) in fns.enumerated() {
            stepStarted(i)
            progress(Double(i) / Double(fns.count))
            f()
            stepDone(i)
            progress(Double(i + 1) / Double(fns.count))
        }
        var s = 100
        s -= min(18, cats.filter { !$0.found.isEmpty && $0.defaultOn }.count * 3)
        s -= res.findings.filter { $0.state == .bad }.count * 8
        s -= res.findings.filter { $0.state == .fix }.count * 3
        let cpu = LiveData.shared.cpu
        if cpu > 50 { s -= 12 } else if cpu > 25 { s -= 6 }
        res.score = max(5, min(100, s))
        return res
    }

    private func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        if size == 0 { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buf, &size, nil, 0)
        return String(cString: buf)
    }

    private func sysInfo() {
        var chip = sysctlString("machdep.cpu.brand_string")
        if chip.isEmpty { chip = sysctlString("hw.model") }
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let ram = Double(ProcessInfo.processInfo.physicalMemory)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        add(.info, "\(chip) · \(cores) cores")
        add(.info, "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
        if ram < 8.5e9 { add(.fix, "\(formatBytes(ram)) memory: tight for sample libraries", tip: "16 GB or more is comfortable for audio work.") }
        else { add(.good, "\(formatBytes(ram)) memory") }
    }

    private func apps() {
        res.daws = Apps.scan(cats)
        for d in res.daws { add(.good, "Audio app running: \(d) (protected)") }
        for c in cats where !c.found.isEmpty {
            add(c.defaultOn ? .fix : .info, "\(c.name): \(c.found.count) app\(c.found.count == 1 ? "" : "s"), \(formatBytes(c.bytes))", tip: c.tip, setting: "app:" + c.id)
        }
        Thread.sleep(forTimeInterval: 0.6)
        let table = Apps.processTable()
        let top = table.values.filter { $0.name != "ADAudioOptimizer" && $0.name != "kernel_task" }.sorted { $0.cpu > $1.cpu }.prefix(3)
        let text = top.isEmpty ? "nothing busy" : top.map { "\($0.name) \(Int($0.cpu.rounded()))%" }.joined(separator: ", ")
        let cpu = LiveData.shared.cpu
        add(cpu > 25 ? .fix : .good, "CPU load \(Int(cpu.rounded()))% · top: \(text)")
    }

    private func agents() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var count = 0
        var names: [String] = []
        for dir in [home + "/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"] {
            if let items = try? fm.contentsOfDirectory(atPath: dir) {
                for i in items where i.hasSuffix(".plist") { count += 1; names.append((i as NSString).deletingPathExtension) }
            }
        }
        if count > 12 {
            add(.fix, "\(count) background agents installed", tip: "Third-party helpers that run in the background: " + names.prefix(20).joined(separator: ", ") + ". Turn off the ones you don't need in System Settings → General → Login Items.")
        } else {
            add(.good, "\(count) background agents installed")
        }
    }

    private func power() {
        let low = Optimizer.lowPowerOn()
        state("lowpower", !low)
        if low { add(.fix, "Low Power Mode is on", tip: "It lowers CPU speed and causes dropouts.", setting: "lowpower") }
        else { add(.good, "Low Power Mode: off") }
        let nap = Optimizer.appNapDisabled()
        state("appnap", nap)
        if !nap { add(.fix, "App Nap is on", tip: "macOS may slow down your DAW when its window is hidden.", setting: "appnap") }
        res.states["nosleep"] = .fix
        state("visual", Optimizer.reduceMotionOn())
        if let v = Optimizer.alertVolume() { state("alerts", v == 0) }
    }

    private func jobs() {
        let spot = Optimizer.spotlightOn()
        state("spotlight", !spot)
        if spot { add(.fix, "Spotlight indexing is on", tip: "Spotlight indexes every new audio file you record.", setting: "spotlight") }
        let tm = Optimizer.timeMachineAuto()
        state("timemachine", !tm)
        if tm { add(.fix, "Time Machine backs up automatically", tip: "A backup can start in the middle of a session.", setting: "timemachine") }
        if !spot && !tm { add(.good, "Spotlight and Time Machine are paused") }
    }

    private func audio() {
        guard let id = Audio.defaultDevice(input: false) else { add(.fix, "No audio output device found"); return }
        let d = Audio.info(id)
        add(d.transport == "Bluetooth" ? .bad : .good, "Output: \(d.name) · \(d.transport) · \(Int(d.sampleRate)) Hz · buffer \(d.bufferFrames)",
            tip: d.transport == "Bluetooth" ? "Bluetooth audio adds 100–300 ms of delay. Use your audio interface or wired headphones for recording." : nil)
        if let inId = Audio.defaultDevice(input: true), inId != id {
            let i = Audio.info(inId)
            if Int(i.sampleRate) != Int(d.sampleRate) {
                add(.fix, "Input \(i.name) runs at \(Int(i.sampleRate)) Hz, output at \(Int(d.sampleRate)) Hz", tip: "Different sample rates force resampling and can cause clicks. Set both to the same rate in the Audio device tab.", setting: "srcheck")
                res.states["srcheck"] = .fix
            } else { res.states["srcheck"] = .good }
            add(i.transport == "Built-in" ? .info : .good, "Input: \(i.name) · \(i.transport)")
        } else { res.states["srcheck"] = .good }
    }

    private func memory() {
        let d = LiveData.shared
        let p = d.pressure
        add(p >= 4 ? .bad : p >= 2 ? .fix : .good, "Memory pressure: " + (p >= 4 ? "high" : p >= 2 ? "warning" : "low") + " · \(formatBytes(d.memUsed)) of \(formatBytes(d.memTotal)) in use",
            tip: p >= 2 ? "macOS is compressing and swapping memory. Close apps or free inactive memory." : nil, setting: p >= 2 ? "purge" : nil)
        res.states["purge"] = p >= 2 ? .fix : .good
    }

    private func disks() {
        for d in Disks.list() {
            let smart = d.smart
            let st: DotState = smart == "Verified" ? .good : (smart == "Not Supported" ? .info : .bad)
            add(st, "\(d.name) · \(d.ssd ? "SSD" : "HDD") · \(formatBytes(d.size)) · SMART: \(smart)",
                tip: st == .bad ? "The disk reports a problem. Back up now and run First Aid in Disk Utility." : nil)
        }
        let fs = Disks.freeSpace()
        let low = fs.free < 20e9
        state("diskcheck", !low)
        let hours = fs.free / (16.0 * 48000 * 3 * 3600)
        add(low ? .bad : .good, "Startup disk: \(formatBytes(fs.free)) free ≈ \(String(format: "%.1f", hours)) h of 16 tracks", setting: low ? "diskcheck" : nil)
    }

    private func network() {
        let wifi = Optimizer.wifiOn()
        state("wifi", !wifi)
        if wifi { add(.fix, "Wi‑Fi is on", tip: "Wi‑Fi scanning can cause short latency spikes. Use a cable or turn Wi‑Fi off if you don't need it.", setting: "wifi") }
        let (c, out) = Shell.run("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.Bluetooth", "ControllerPowerState"])
        if c == 0 && out.trimmingCharacters(in: .whitespacesAndNewlines) == "1" { add(.info, "Bluetooth is on", tip: "Turn it off in Control Center if you don't use Bluetooth devices.") }
    }

    private func latency() {
        LiveData.shared.latencyPaused = true
        let n = Double(DeepScan.steps.count)
        res.latency = LiveData.measure(seconds: 8) { p in self.progress((n - 1 + p) / n) }
        LiveData.shared.latencyPaused = false
        let us = res.latency.max
        let s: DotState = us < 300 ? .good : us < 1000 ? .fix : .bad
        let verdict = us < 250 ? "great for 32–64 sample buffers" : us < 500 ? "good for 64–128 samples" : us < 1000 ? "OK for 128–256 samples" : "high: use 256–512 samples"
        add(s, "Latency max \(Int(us.rounded())) µs · \(verdict)", tip: "Longest wake-up delay of a timer thread over 8 seconds. 99% were under \(Int(res.latency.p99.rounded())) µs.")
    }
}

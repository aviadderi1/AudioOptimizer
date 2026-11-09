import AppKit

/// Applies and restores the optimizations. Root commands are batched into one password prompt.
final class Optimizer {
    let backup = Backup()
    private var caffeinate: Process?
    private(set) var log: [String] = []
    static let ok = "✔ ", fail = "✖ ", info = "• "

    // MARK: helpers

    private func wifiDevice() -> String? {
        let (_, out) = Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"])
        let lines = out.components(separatedBy: "\n")
        for (i, l) in lines.enumerated() where l.contains("Wi-Fi") || l.contains("AirPort") {
            if i + 1 < lines.count, lines[i + 1].hasPrefix("Device:") { return lines[i + 1].replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    static func lowPowerOn() -> Bool {
        let (_, out) = Shell.run("/usr/bin/pmset", ["-g"])
        for l in out.components(separatedBy: "\n") where l.contains("lowpowermode") {
            return l.trimmingCharacters(in: .whitespaces).hasSuffix("1")
        }
        return false
    }

    static func spotlightOn() -> Bool {
        let (_, out) = Shell.run("/usr/bin/mdutil", ["-s", "/"])
        return out.contains("enabled")
    }

    static func timeMachineAuto() -> Bool {
        let (code, out) = Shell.run("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.TimeMachine", "AutoBackup"])
        return code == 0 && out.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    static func appNapDisabled() -> Bool {
        let (code, out) = Shell.run("/usr/bin/defaults", ["read", "NSGlobalDomain", "NSAppSleepDisabled"])
        return code == 0 && out.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    static func reduceMotionOn() -> Bool {
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func alertVolume() -> Int? {
        let (code, out) = Shell.run("/usr/bin/osascript", ["-e", "alert volume of (get volume settings)"])
        return code == 0 ? Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
    }

    static func wifiOn() -> Bool {
        let o = Optimizer()
        guard let dev = o.wifiDevice() else { return false }
        let (_, out) = Shell.run("/usr/sbin/networksetup", ["-getairportpower", dev])
        return out.contains(": On")
    }

    // MARK: apply

    func apply(_ sel: Set<String>, cats: [AppCategory], progress: @escaping (String) -> Void) -> [String] {
        log = []

        // apps
        progress("Closing background apps…")
        for c in cats where sel.contains("app:" + c.id) && !c.found.isEmpty {
            var closed = 0
            for a in c.found where !a.isTerminated { if a.terminate() { closed += 1 } }
            Thread.sleep(forTimeInterval: 2)
            for a in c.found where !a.isTerminated { a.forceTerminate() }
            log.append(Optimizer.ok + "Closed \(c.name) (\(c.found.count) app\(c.found.count == 1 ? "" : "s"))")
        }

        // user-level settings (no password)
        if sel.contains("nosleep") {
            if caffeinate == nil || !(caffeinate!.isRunning) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
                p.arguments = ["-dimsu", "-w", String(ProcessInfo.processInfo.processIdentifier)]
                do { try p.run(); caffeinate = p; backup.add("runtime|nosleep", "1"); log.append(Optimizer.ok + "Prevent sleep (while the app is open)") }
                catch { log.append(Optimizer.fail + "Prevent sleep (\(error.localizedDescription))") }
            } else { log.append(Optimizer.ok + "Prevent sleep (already on)") }
        }
        if sel.contains("appnap") {
            if Optimizer.appNapDisabled() { log.append(Optimizer.ok + "App Nap off (already off)") }
            else {
                backup.add("appnap", "on")
                let (c, o) = Shell.run("/usr/bin/defaults", ["write", "NSGlobalDomain", "NSAppSleepDisabled", "-bool", "YES"])
                log.append(c == 0 ? Optimizer.ok + "App Nap off (for apps opened from now on)" : Optimizer.fail + "App Nap off (\(o.trimmingCharacters(in: .whitespacesAndNewlines)))")
            }
        }
        if sel.contains("visual") {
            let wasMotion = Optimizer.reduceMotionOn()
            if !wasMotion { backup.add("visual", "off") }
            let a = Shell.run("/usr/bin/defaults", ["write", "com.apple.universalaccess", "reduceMotion", "-bool", "true"]).0
            let b = Shell.run("/usr/bin/defaults", ["write", "com.apple.universalaccess", "reduceTransparency", "-bool", "true"]).0
            if a == 0 && b == 0 { log.append(Optimizer.ok + "Reduce motion and transparency") }
            else {
                backup.remove("visual")
                log.append(Optimizer.fail + "Reduce motion and transparency (macOS blocks this. Turn it on in System Settings → Accessibility → Display)")
            }
        }
        if sel.contains("alerts") {
            if let v = Optimizer.alertVolume(), v > 0 {
                backup.add("alerts", String(v))
                Shell.run("/usr/bin/osascript", ["-e", "set volume alert volume 0"])
                log.append(Optimizer.ok + "Mute system alert sounds")
            } else { log.append(Optimizer.ok + "Mute system alert sounds (already muted)") }
        }

        // root batch
        var script = ""
        var labels: [String: String] = [:]
        func add(_ id: String, _ label: String, _ cmd: String) {
            labels[id] = label
            script += "if \(cmd) >/dev/null 2>&1; then echo 'OK:\(id)'; else echo 'FAIL:\(id)'; fi\n"
        }
        if sel.contains("lowpower") && Optimizer.lowPowerOn() { backup.add("lowpower", "1"); add("lowpower", "Low Power Mode off", "/usr/bin/pmset -a lowpowermode 0") }
        if sel.contains("spotlight") && Optimizer.spotlightOn() { backup.add("spotlight", "on"); add("spotlight", "Pause Spotlight indexing", "/usr/bin/mdutil -a -i off") }
        if sel.contains("timemachine") && Optimizer.timeMachineAuto() { backup.add("timemachine", "on"); add("timemachine", "Pause Time Machine", "/usr/bin/tmutil disable") }
        if sel.contains("swupdate") { backup.add("swupdate", "on"); add("swupdate", "Pause software update checks", "/usr/sbin/softwareupdate --schedule off") }
        if sel.contains("purge") { add("purge", "Free inactive memory", "/usr/sbin/purge") }
        if sel.contains("wifi"), let dev = wifiDevice(), Optimizer.wifiOn() {
            backup.add("wifi|" + dev, "on")
            add("wifi", "Turn off Wi‑Fi", "/usr/sbin/networksetup -setairportpower \(dev) off")
        }
        if sel.contains("dawprio") {
            let daws = NSWorkspace.shared.runningApplications.filter { Apps.isProtected($0) && $0.activationPolicy == .regular }
            if daws.isEmpty { log.append(Optimizer.info + "DAW priority: no DAW running right now") }
            else {
                backup.add("runtime|dawprio", daws.map { String($0.processIdentifier) }.joined(separator: ","))
                add("dawprio", "DAW process priority high", "/usr/bin/renice -n -10 -p " + daws.map { String($0.processIdentifier) }.joined(separator: " "))
            }
        }
        if !script.isEmpty {
            progress("Waiting for your password…")
            let (ok, out) = Shell.admin(script)
            if !ok && !out.contains("OK:") && !out.contains("FAIL:") {
                for id in labels.keys { log.append(Optimizer.fail + labels[id]! + " (password not given)") }
                for k in ["lowpower", "spotlight", "timemachine", "swupdate"] where labels[k] != nil { backup.remove(k) }
                backup.items.filter { $0.0.hasPrefix("wifi|") || $0.0 == "runtime|dawprio" }.forEach { backup.remove($0.0) }
            } else {
                for line in out.components(separatedBy: CharacterSet.newlines) {
                    if line.hasPrefix("OK:"), let l = labels[String(line.dropFirst(3))] { log.append(Optimizer.ok + l) }
                    if line.hasPrefix("FAIL:"), let l = labels[String(line.dropFirst(5))] { log.append(Optimizer.fail + l) }
                }
            }
        }

        if sel.contains("srcheck") {
            if let id = Audio.defaultDevice(input: false) {
                let d = Audio.info(id)
                log.append(Optimizer.info + "Audio: \(d.name) · \(Int(d.sampleRate)) Hz · buffer \(d.bufferFrames)")
            }
        }
        if sel.contains("diskcheck") {
            let fs = Disks.freeSpace()
            let hours = fs.free / (16.0 * 48000 * 3 * 3600)
            log.append((fs.free < 20e9 ? Optimizer.fail : Optimizer.info) + "Disk: \(formatBytes(fs.free)) free ≈ \(String(format: "%.1f", hours)) h of 16-track 48k/24-bit")
        }
        return log
    }

    // MARK: restore

    func restore(progress: @escaping (String) -> Void) -> [String] {
        log = []
        var script = ""
        for (k, v) in backup.items.reversed() {
            switch k {
            case "lowpower": script += "/usr/bin/pmset -a lowpowermode 1\n"
            case "spotlight": script += "/usr/bin/mdutil -a -i on\n"
            case "timemachine": script += "/usr/bin/tmutil enable\n"
            case "swupdate": script += "/usr/sbin/softwareupdate --schedule on\n"
            case "runtime|dawprio": script += "/usr/bin/renice -n 0 -p " + v.replacingOccurrences(of: ",", with: " ") + "\n"
            case "appnap": Shell.run("/usr/bin/defaults", ["delete", "NSGlobalDomain", "NSAppSleepDisabled"]); log.append(Optimizer.ok + "App Nap back on")
            case "visual":
                Shell.run("/usr/bin/defaults", ["write", "com.apple.universalaccess", "reduceMotion", "-bool", "false"])
                Shell.run("/usr/bin/defaults", ["write", "com.apple.universalaccess", "reduceTransparency", "-bool", "false"])
                log.append(Optimizer.ok + "Motion and transparency restored")
            case "alerts": Shell.run("/usr/bin/osascript", ["-e", "set volume alert volume \(v)"]); log.append(Optimizer.ok + "Alert sounds restored")
            case "runtime|nosleep": caffeinate?.terminate(); caffeinate = nil; log.append(Optimizer.ok + "Sleep allowed again")
            default:
                if k.hasPrefix("wifi|") { script += "/usr/sbin/networksetup -setairportpower \(k.dropFirst(5)) on\n" }
            }
        }
        if !script.isEmpty {
            progress("Waiting for your password…")
            let (ok, _) = Shell.admin(script)
            log.append((ok ? Optimizer.ok : Optimizer.fail) + (ok ? "System settings restored (power, Spotlight, Time Machine, updates, Wi‑Fi)" : "System settings not restored (password not given). Press Restore defaults again."))
            if !ok { return log }
        }
        backup.clear()
        return log
    }

    func keepRuntime() {
        if backup.has("runtime|nosleep") && caffeinate == nil {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            p.arguments = ["-dimsu", "-w", String(ProcessInfo.processInfo.processIdentifier)]
            try? p.run()
            caffeinate = p
        }
    }
}

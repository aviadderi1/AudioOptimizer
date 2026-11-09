import AppKit
import CoreAudio

// MARK: - Apps

final class AppCategory {
    let id: String, name: String, tip: String
    let defaultOn: Bool
    let bundlePrefixes: [String]
    var found: [NSRunningApplication] = []
    var bytes: Double = 0

    init(_ id: String, _ name: String, _ tip: String, _ on: Bool, _ prefixes: [String]) {
        self.id = id; self.name = name; self.tip = tip; defaultOn = on; bundlePrefixes = prefixes
    }

    var summary: String {
        let names = Array(Set(found.compactMap { $0.localizedName })).sorted().prefix(3)
        return name + " · " + names.joined(separator: ", ") + (bytes > 0 ? " · " + formatBytes(bytes) : "")
    }
}

enum Apps {
    static func categories() -> [AppCategory] {
        return [
            AppCategory("browsers", "Browsers", "Browsers keep tabs, video and extensions running in the background. Closing them frees memory and stops CPU spikes.", true,
                        ["com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "company.thebrowser.Browser"]),
            AppCategory("cloud", "Cloud sync", "Cloud sync uploads and downloads files at random times, hitting the disk and network mid-take.", true,
                        ["com.getdropbox.dropbox", "com.microsoft.OneDrive", "com.google.drivefs", "com.google.GoogleDrive", "com.pcloud", "nz.mega"]),
            AppCategory("games", "Game launchers and Discord", "Game launchers update games in the background. Discord also grabs audio devices.", true,
                        ["com.valvesoftware.steam", "com.epicgames", "com.hnc.Discord", "com.blizzard", "com.riotgames"]),
            AppCategory("chat", "Chat and mail", "Chat and mail apps play notification sounds and can take over your audio device during calls.", true,
                        ["com.apple.MobileSMS", "net.whatsapp.WhatsApp", "desktop.WhatsApp", "ru.keepcoder.Telegram", "org.telegram", "com.microsoft.teams", "com.tinyspeck.slackmacgap", "us.zoom.xos", "com.skype", "com.facebook.archon", "com.apple.mail", "com.microsoft.Outlook", "com.apple.FaceTime"]),
            AppCategory("updaters", "Updaters", "Creative Cloud and other updaters wake up on their own schedule and download in the background.", true,
                        ["com.adobe.acc", "com.adobe.AdobeResourceSynchronizer", "com.adobe.ccx"]),
            AppCategory("media", "Media players", "Music and video players hold the audio device. Off by default in case you play reference tracks.", false,
                        ["com.spotify.client", "com.apple.Music", "com.apple.TV", "org.videolan.vlc", "com.apple.podcasts"]),
        ]
    }

    static let dawPrefixes = ["com.apple.logic", "com.apple.mainstage", "com.apple.garageband", "com.ableton", "com.steinberg", "com.image-line", "com.presonus",
                              "com.bitwig", "com.avid", "com.cockos", "com.motu", "com.native-instruments", "com.waves", "com.reasonstudios", "com.propellerheads",
                              "com.audiodamage", "com.celemony", "com.izotope", "com.serato", "com.atomixproductions.virtualDJ", "com.pioneerdj", "com.apple.audio.AudioMIDISetup",
                              "com.focusrite", "com.universal-audio", "com.rme", "com.gigperformer", "com.audiolabs", "com.apple.FinalCut"]

    static func isProtected(_ app: NSRunningApplication) -> Bool {
        let b = (app.bundleIdentifier ?? "").lowercased()
        return dawPrefixes.contains { b.hasPrefix($0.lowercased()) }
    }

    /// pid → (rss bytes, %cpu, command)
    static func processTable() -> [Int32: (rss: Double, cpu: Double, name: String)] {
        let (_, out) = Shell.run("/bin/ps", ["-axo", "pid=,rss=,%cpu=,comm="])
        var t: [Int32: (rss: Double, cpu: Double, name: String)] = [:]
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            if parts.count < 4 { continue }
            guard let pid = Int32(parts[0]), let rss = Double(parts[1]) else { continue }
            let cpu = Double(parts[2].replacingOccurrences(of: ",", with: ".")) ?? 0
            let name = (String(parts[3]) as NSString).lastPathComponent
            t[pid] = (rss * 1024, cpu, name)
        }
        return t
    }

    static func scan(_ cats: [AppCategory]) -> [String] {
        for c in cats { c.found = []; c.bytes = 0 }
        let table = processTable()
        var daws: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let b = app.bundleIdentifier else { continue }
            if isProtected(app) {
                if app.activationPolicy == .regular { daws.append(app.localizedName ?? b) }
                continue
            }
            for c in cats where c.bundlePrefixes.contains(where: { b.hasPrefix($0) }) {
                c.found.append(app)
                c.bytes += table[app.processIdentifier]?.rss ?? 0
                break
            }
        }
        return Array(Set(daws)).sorted()
    }
}

// MARK: - Settings items

struct Item {
    let id: String, label: String, tip: String
}

struct Section {
    let title: String, tip: String
    let items: [Item]
}

enum Catalog {
    static let sections: [Section] = [
        Section(title: "Power and system", tip: "Keeps the Mac at full speed: no Low Power Mode, no sleep, no App Nap. App Nap can slow down your DAW when its window is in the background.", items: [
            Item(id: "lowpower", label: "Low Power Mode off", tip: "Low Power Mode lowers CPU speed to save battery, which causes dropouts."),
            Item(id: "nosleep", label: "Prevent sleep (display and disk)", tip: "The Mac, display and disk won't sleep while AD Audio Optimizer is open."),
            Item(id: "appnap", label: "App Nap off", tip: "macOS slows down apps whose windows are hidden. This turns that off for apps you open after OPT."),
            Item(id: "visual", label: "Reduce motion and transparency", tip: "Turns off animations and transparency to take load off the graphics chip. May need permission in System Settings."),
        ]),
        Section(title: "Background jobs", tip: "Pauses macOS background jobs that can wake up mid-take: Spotlight indexing, Time Machine backups and update checks. They come back with Restore defaults.", items: [
            Item(id: "spotlight", label: "Pause Spotlight indexing", tip: "Stops Spotlight from indexing new audio files while you record."),
            Item(id: "timemachine", label: "Pause Time Machine", tip: "No automatic backups during the session."),
            Item(id: "swupdate", label: "Pause software update checks", tip: "No automatic update checks or downloads during the session."),
        ]),
        Section(title: "Audio", tip: "Gives your DAW priority and silences system sounds that could land in a recording.", items: [
            Item(id: "dawprio", label: "DAW process priority high", tip: "Raises the priority of running audio apps (Logic, Ableton, Cubase and more)."),
            Item(id: "alerts", label: "Mute system alert sounds", tip: "No alert beeps going through your audio interface."),
            Item(id: "srcheck", label: "Check sample rate and buffer", tip: "Reports the current audio device, sample rate and buffer size, and warns about mismatches."),
        ]),
        Section(title: "Memory and network", tip: "Frees inactive memory, checks disk space and lets you switch off Wi‑Fi, a common cause of latency spikes.", items: [
            Item(id: "purge", label: "Free inactive memory", tip: "Runs macOS 'purge' to free cached memory for sample libraries."),
            Item(id: "wifi", label: "Turn off Wi‑Fi", tip: "Leave on if your plugins need online licenses or you control a mixer from a tablet."),
            Item(id: "diskcheck", label: "Check disk free space", tip: "Shows how many hours of 16-track 48 kHz / 24-bit recording fit on the disk."),
        ]),
    ]

    static let profiles = ["Recording", "Mixing", "Live show", "Custom"]
    static let profileDesc = ["Recording: lowest latency, everything paused.", "Mixing: everything on, Wi‑Fi stays on for plugin licenses.",
                              "Live show: Wi‑Fi stays on for tablet mixer control.", "Custom: your own selection of settings."]
    static let base: Set<String> = ["lowpower", "nosleep", "appnap", "visual", "spotlight", "timemachine", "swupdate", "dawprio", "alerts", "srcheck", "purge", "diskcheck"]

    static func profileSet(_ p: Int) -> Set<String> {
        var s = base
        if p == 1 { s.remove("purge") }
        return s
    }
}

// MARK: - Audio device (CoreAudio)

struct AudioDevice {
    let id: AudioDeviceID
    let name: String
    let sampleRate: Double
    let bufferFrames: UInt32
    let rates: [Double]
    let inputs: Int, outputs: Int
    let transport: String
}

enum Audio {
    private static func addr(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        return AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultDevice(input: Bool) -> AudioDeviceID? {
        var a = addr(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let r = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return r == noErr && id != 0 ? id : nil
    }

    static func allDevices() -> [AudioDeviceID] {
        var a = addr(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func info(_ id: AudioDeviceID) -> AudioDevice {
        var a = addr(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var n = "Unknown device"
        if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &name) == noErr, let cf = name?.takeRetainedValue() { n = cf as String }

        a = addr(kAudioDevicePropertyNominalSampleRate)
        var rate = Float64(0)
        size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &rate)

        a = addr(kAudioDevicePropertyBufferFrameSize)
        var frames = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &frames)

        a = addr(kAudioDevicePropertyAvailableNominalSampleRates)
        var rates: [Double] = []
        if AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr && size > 0 {
            var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
            if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &ranges) == noErr {
                rates = ranges.map { $0.mMaximum }
            }
        }

        func streams(_ scope: AudioObjectPropertyScope) -> Int {
            var sa = addr(kAudioDevicePropertyStreams, scope)
            var s: UInt32 = 0
            return AudioObjectGetPropertyDataSize(id, &sa, 0, nil, &s) == noErr ? Int(s) / MemoryLayout<AudioStreamID>.size : 0
        }

        a = addr(kAudioDevicePropertyTransportType)
        var tt = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &tt)
        let transport: String
        switch tt {
        case kAudioDeviceTransportTypeBuiltIn: transport = "Built-in"
        case kAudioDeviceTransportTypeUSB: transport = "USB"
        case kAudioDeviceTransportTypeThunderbolt: transport = "Thunderbolt"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: transport = "Bluetooth"
        case kAudioDeviceTransportTypeAggregate: transport = "Aggregate"
        case kAudioDeviceTransportTypeVirtual: transport = "Virtual"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: transport = "Display"
        case kAudioDeviceTransportTypeAVB: transport = "AVB"
        default: transport = "Other"
        }
        return AudioDevice(id: id, name: n, sampleRate: rate, bufferFrames: frames, rates: Array(Set(rates)).sorted(), inputs: streams(kAudioObjectPropertyScopeInput), outputs: streams(kAudioObjectPropertyScopeOutput), transport: transport)
    }

    @discardableResult
    static func setSampleRate(_ id: AudioDeviceID, _ rate: Double) -> Bool {
        var a = addr(kAudioDevicePropertyNominalSampleRate)
        var r = Float64(rate)
        return AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float64>.size), &r) == noErr
    }
}

// MARK: - Disks

struct DiskInfo {
    let id: String, name: String, size: Double, ssd: Bool, smart: String, bus: String, isInternal: Bool
}

enum Disks {
    static func plist(_ args: [String]) -> [String: Any]? {
        let (code, out) = Shell.run("/usr/sbin/diskutil", args)
        guard code == 0, let d = out.data(using: .utf8) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: d, options: [], format: nil)) as? [String: Any]
    }

    static func list() -> [DiskInfo] {
        guard let l = plist(["list", "-plist", "physical"]), let whole = l["WholeDisks"] as? [String] else { return [] }
        return whole.compactMap { id in
            guard let i = plist(["info", "-plist", id]) else { return nil }
            return DiskInfo(id: id, name: (i["MediaName"] as? String) ?? id, size: (i["Size"] as? Double) ?? Double((i["TotalSize"] as? Int) ?? 0),
                            ssd: (i["SolidState"] as? Bool) ?? false, smart: (i["SMARTStatus"] as? String) ?? "Not Supported",
                            bus: (i["BusProtocol"] as? String) ?? "", isInternal: (i["Internal"] as? Bool) ?? false)
        }
    }

    static func freeSpace() -> (free: Double, total: Double) {
        let url = URL(fileURLWithPath: "/")
        if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            return (Double(v.volumeAvailableCapacityForImportantUsage ?? 0), Double(v.volumeTotalCapacity ?? 0))
        }
        return (0, 0)
    }
}

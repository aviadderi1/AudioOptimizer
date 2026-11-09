import Foundation

enum Shell {
    /// Runs a command and returns (exit code, combined output).
    @discardableResult
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 60) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        let handle = pipe.fileHandleForReading
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            data = handle.readDataToEndOfFile()
            group.leave()
        }
        while p.isRunning && Date() < deadline { usleep(20000) }
        if p.isRunning { p.terminate(); return (-1, "timeout") }
        _ = group.wait(timeout: .now() + 2)
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    static func sh(_ command: String, timeout: TimeInterval = 60) -> (Int32, String) {
        return run("/bin/sh", ["-c", command], timeout: timeout)
    }

    /// Runs a shell script as root through the standard macOS password prompt.
    /// One prompt for the whole batch. Returns (ok, output).
    static func admin(_ script: String, timeout: TimeInterval = 600) -> (Bool, String) {
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("adopt-\(UUID().uuidString).sh")
        do { try ("#!/bin/sh\n" + script).write(to: file, atomically: true, encoding: .utf8) } catch { return (false, error.localizedDescription) }
        defer { try? FileManager.default.removeItem(at: file) }
        let apple = "do shell script \"/bin/sh '\(file.path)' 2>&1\" with administrator privileges with prompt \"AD Audio Optimizer needs your password to change system settings.\""
        let (code, out) = run("/usr/bin/osascript", ["-e", apple], timeout: timeout)
        return (code == 0, out)
    }

    static func shellQuote(_ s: String) -> String {
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Ordered key/value backup of every original setting we change. Saved to disk.
final class Backup {
    private(set) var items: [(String, String)] = []
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ADAudioOptimizer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("backup.json")
        if let d = try? Data(contentsOf: url), let arr = try? JSONSerialization.jsonObject(with: d) as? [[String]] {
            items = arr.compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
        }
    }

    var active: Bool { return !items.isEmpty }
    func has(_ k: String) -> Bool { return items.contains { $0.0 == k } }
    func get(_ k: String) -> String? { return items.first { $0.0 == k }?.1 }

    func add(_ k: String, _ v: String) {
        if has(k) { return }
        items.append((k, v))
        save()
    }

    func remove(_ k: String) { items.removeAll { $0.0 == k }; save() }

    func clear() { items.removeAll(); try? FileManager.default.removeItem(at: url) }

    private func save() {
        let arr = items.map { [$0.0, $0.1] }
        if let d = try? JSONSerialization.data(withJSONObject: arr) { try? d.write(to: url) }
    }
}

final class Settings {
    private var values: [String: String] = [:]
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ADAudioOptimizer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("settings.json")
        if let d = try? Data(contentsOf: url), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: String] { values = obj }
    }

    func get(_ k: String) -> String? { return values[k] }
    func set(_ k: String, _ v: String) { values[k] = v }
    func save() {
        if let d = try? JSONSerialization.data(withJSONObject: values) { try? d.write(to: url) }
    }
}

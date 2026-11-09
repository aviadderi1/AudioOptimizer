import Foundation
import Darwin

/// Samples CPU per core, memory and timer latency twice a second.
final class LiveData {
    static let shared = LiveData()

    private(set) var cores: [Double] = []
    private(set) var cpuHistory: [Double] = []
    private(set) var memHistory: [Double] = []
    private(set) var latHistory: [Double] = []
    private(set) var pressure: Int = 1          // 1 normal, 2 warning, 4 critical
    private(set) var memUsed: Double = 0
    private(set) var memTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    var latencyPaused = false

    var cpu: Double { return cpuHistory.last ?? 0 }
    var mem: Double { return memHistory.last ?? 0 }
    var lat: Double { return latHistory.last ?? 0 }

    private var prevTicks: [(busy: Double, total: Double)] = []
    private var timer: Timer?
    private var latThread: Thread?
    private let lock = NSLock()
    private var latWindowMax: Double = -1
    var onSample: [() -> Void] = []

    func start() {
        if timer != nil { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer!, forMode: .common)
        let t = Thread { [weak self] in self?.latencyLoop() }
        t.qualityOfService = .userInteractive
        t.start()
        latThread = t
    }

    private func push(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > 120 { arr.removeFirst(arr.count - 120) }
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        lock.lock()
        let l = latWindowMax
        latWindowMax = -1
        lock.unlock()
        if !latencyPaused && l >= 0 { push(&latHistory, l) }
        for f in onSample { f() }
    }

    private func sampleCPU() {
        var numCPUs: natural_t = 0
        var info: processor_info_array_t?
        var numInfo: mach_msg_type_number_t = 0
        let r = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &info, &numInfo)
        guard r == KERN_SUCCESS, let cpuInfo = info else { return }
        var now: [(busy: Double, total: Double)] = []
        for i in 0..<Int(numCPUs) {
            let base = Int(CPU_STATE_MAX) * i
            let user = Double(cpuInfo[base + Int(CPU_STATE_USER)])
            let sys = Double(cpuInfo[base + Int(CPU_STATE_SYSTEM)])
            let nice = Double(cpuInfo[base + Int(CPU_STATE_NICE)])
            let idle = Double(cpuInfo[base + Int(CPU_STATE_IDLE)])
            now.append((busy: user + sys + nice, total: user + sys + nice + idle))
        }
        let size = vm_size_t(Int(numInfo) * MemoryLayout<integer_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)

        var per: [Double] = []
        if prevTicks.count == now.count {
            for i in 0..<now.count {
                let dt = now[i].total - prevTicks[i].total
                let db = now[i].busy - prevTicks[i].busy
                per.append(dt > 0 ? max(0, min(100, db / dt * 100)) : 0)
            }
        } else {
            per = Array(repeating: 0, count: now.count)
        }
        prevTicks = now
        cores = per
        push(&cpuHistory, per.isEmpty ? 0 : per.reduce(0, +) / Double(per.count))
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        if kr == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
            memUsed = used
            push(&memHistory, memTotal > 0 ? min(100, used / memTotal * 100) : 0)
        }
        var level: Int32 = 1
        var len = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &len, nil, 0) == 0 { pressure = Int(level) }
    }

    private func latencyLoop() {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let toNs = Double(tb.numer) / Double(tb.denom)
        let interval = UInt64(1_000_000.0 / toNs) // 1 ms in ticks
        while true {
            if latencyPaused { usleep(200_000); continue }
            let start = mach_absolute_time()
            mach_wait_until(start + interval)
            let elapsedUs = Double(mach_absolute_time() - start) * toNs / 1000.0
            let over = max(0, elapsedUs - 1000)
            lock.lock()
            if over > latWindowMax { latWindowMax = over }
            lock.unlock()
        }
    }

    /// One-off latency measurement for scans and the latency test.
    static func measure(seconds: Double, progress: ((Double) -> Void)? = nil) -> (max: Double, p99: Double, avg: Double) {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let toNs = Double(tb.numer) / Double(tb.denom)
        let interval = UInt64(1_000_000.0 / toNs)
        var samples: [Double] = []
        let begin = Date()
        var lastReport = -1
        while Date().timeIntervalSince(begin) < seconds {
            let start = mach_absolute_time()
            mach_wait_until(start + interval)
            let us = Double(mach_absolute_time() - start) * toNs / 1000.0
            samples.append(max(0, us - 1000))
            let pct = Int(Date().timeIntervalSince(begin) / seconds * 100)
            if pct != lastReport { lastReport = pct; progress?(min(1, Double(pct) / 100)) }
        }
        if samples.isEmpty { return (0, 0, 0) }
        let sorted = samples.sorted()
        return (sorted.last!, sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))], samples.reduce(0, +) / Double(samples.count))
    }
}

import AppKit
import Foundation
import IOKit
import IOKit.ps
import Metal
import SystemConfiguration

// MARK: - Activity Monitor Navigation Helper
enum SystemActivityNavigator {
    @MainActor
    static func open(tab: String?) {
        // Tab names for Activity Monitor: "CPU", "Memory", "Energy", "Disk", "Network"
        let script: String
        switch tab {
        case "CPU":
            script = """
            tell application "Activity Monitor"
                activate
            end tell
            tell application "System Events" to tell process "Activity Monitor"
                try
                    click radio button "CPU" of radio group 1 of group 1 of toolbar 1 of window 1
                end try
            end tell
            """
        case "Memory":
            script = """
            tell application "Activity Monitor"
                activate
            end tell
            tell application "System Events" to tell process "Activity Monitor"
                try
                    click radio button "Memory" of radio group 1 of group 1 of toolbar 1 of window 1
                end try
            end tell
            """
        case "Energy":
            script = """
            tell application "Activity Monitor"
                activate
            end tell
            tell application "System Events" to tell process "Activity Monitor"
                try
                    click radio button "Energy" of radio group 1 of group 1 of toolbar 1 of window 1
                end try
            end tell
            """
        case "Disk":
            script = """
            tell application "Activity Monitor"
                activate
            end tell
            tell application "System Events" to tell process "Activity Monitor"
                try
                    click radio button "Disk" of radio group 1 of group 1 of toolbar 1 of window 1
                end try
            end tell
            """
        case "Network":
            script = """
            tell application "Activity Monitor"
                activate
            end tell
            tell application "System Events" to tell process "Activity Monitor"
                try
                    click radio button "Network" of radio group 1 of group 1 of toolbar 1 of window 1
                end try
            end tell
            """
        case "GPU":
            script = """
            tell application "Activity Monitor"
                activate
            end tell
            tell application "System Events" to tell process "Activity Monitor"
                try
                    click radio button "CPU" of radio group 1 of group 1 of toolbar 1 of window 1
                end try
            end tell
            """
        default:
            script = """
            tell application "Activity Monitor"
                activate
            end tell
            """
        }

        DispatchQueue.global(qos: .userInitiated).async {
            if let appleScript = NSAppleScript(source: script) {
                var errorInfo: NSDictionary?
                appleScript.executeAndReturnError(&errorInfo)
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
                DispatchQueue.main.async {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                }
            }
        }
    }
}

// MARK: - RAM Provider
actor RAMProvider: UsageProvider {
    nonisolated let id = "system-ram"
    nonisolated let displayName = "RAM"
    nonisolated let glyph = ProviderGlyph.ram
    nonisolated let signInRoute = SignInRoute.guidance(L10n.t("System Activity Monitor"))

    init() {}

    nonisolated func account() -> ProviderAccount? {
        let totalGB = String(format: "%.0f GB", Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0)
        return ProviderAccount(label: "System Memory (\(totalGB))", plan: nil, source: "macOS", manageURL: nil)
    }

    func signOut() async {}
    nonisolated func forgetCachedCredential() {}

    func fetchSnapshot() async throws -> ProviderSnapshot {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        var usedFraction = 0.0
        var usedGB = 0.0
        var appGB = 0.0
        var wiredGB = 0.0
        var compressedGB = 0.0
        var freeGB = 0.0

        if result == KERN_SUCCESS {
            let pageSize = Double(vm_kernel_page_size)
            let active = Double(vmStats.active_count) * pageSize
            let wired = Double(vmStats.wire_count) * pageSize
            let compressed = Double(vmStats.compressor_page_count) * pageSize
            let purgeable = Double(vmStats.purgeable_count) * pageSize
            let free = Double(vmStats.free_count) * pageSize

            let usedBytes = active + wired + compressed - purgeable
            usedFraction = min(max(usedBytes / totalBytes, 0), 1)
            usedGB = usedBytes / 1_073_741_824.0
            appGB = (active - purgeable) / 1_073_741_824.0
            wiredGB = wired / 1_073_741_824.0
            compressedGB = compressed / 1_073_741_824.0
            freeGB = free / 1_073_741_824.0
        }

        // Query swap memory usage via sysctl
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapUsedGB = 0.0
        var swapTotalGB = 0.0
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            swapUsedGB = Double(swapUsage.xsu_used) / 1_073_741_824.0
            swapTotalGB = Double(swapUsage.xsu_total) / 1_073_741_824.0
        }

        let totalGBNum = totalBytes / 1_073_741_824.0
        let formattedUsed = String(format: "%.1f GB", usedGB)
        let formattedTotal = String(format: "%.0f GB", totalGBNum)

        let primaryWindow = LimitWindow(
            id: "ram-usage",
            label: L10n.t("Memory Used"),
            usedFraction: usedFraction,
            usedText: formattedUsed,
            detail: "\(formattedUsed) / \(formattedTotal)"
        )

        let appWindow = LimitWindow(
            id: "ram-app",
            label: L10n.t("App Memory"),
            usedText: String(format: "%.1f GB", max(0, appGB))
        )

        let wiredWindow = LimitWindow(
            id: "ram-wired",
            label: L10n.t("Wired Memory"),
            usedText: String(format: "%.1f GB", max(0, wiredGB))
        )

        let compressedWindow = LimitWindow(
            id: "ram-compressed",
            label: L10n.t("Compressed"),
            usedText: String(format: "%.1f GB", max(0, compressedGB))
        )

        let freeWindow = LimitWindow(
            id: "ram-free",
            label: L10n.t("Free Memory"),
            usedText: String(format: "%.1f GB", max(0, freeGB))
        )

        let swapDetail = swapTotalGB > 0
            ? String(format: "%.1f GB / %.1f GB", swapUsedGB, swapTotalGB)
            : String(format: "%.1f GB", swapUsedGB)
        let swapWindow = LimitWindow(
            id: "ram-swap",
            label: L10n.t("Swap Used"),
            usedText: swapDetail
        )

        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: [primaryWindow, appWindow, wiredWindow, compressedWindow, freeWindow, swapWindow],
            headlineID: "ram-usage"
        )
    }
}

// MARK: - CPU Provider
actor CPUProvider: UsageProvider {
    nonisolated let id = "system-cpu"
    nonisolated let displayName = "CPU"
    nonisolated let glyph = ProviderGlyph.cpu
    nonisolated let signInRoute = SignInRoute.guidance(L10n.t("System Activity Monitor"))

    private var previousInfo: host_cpu_load_info?

    init() {}

    nonisolated func account() -> ProviderAccount? {
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        return ProviderAccount(label: "\(coreCount) Cores", plan: nil, source: "macOS", manageURL: nil)
    }

    func signOut() async {}
    nonisolated func forgetCachedCredential() {}

    func fetchSnapshot() async throws -> ProviderSnapshot {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        var cpuFraction = 0.0
        var userPercent = 0
        var sysPercent = 0

        if result == KERN_SUCCESS {
            if let prev = previousInfo {
                let userDelta = Double(cpuInfo.cpu_ticks.0 - prev.cpu_ticks.0)
                let sysDelta = Double(cpuInfo.cpu_ticks.1 - prev.cpu_ticks.1)
                let idleDelta = Double(cpuInfo.cpu_ticks.2 - prev.cpu_ticks.2)
                let niceDelta = Double(cpuInfo.cpu_ticks.3 - prev.cpu_ticks.3)

                let totalDelta = userDelta + sysDelta + idleDelta + niceDelta
                if totalDelta > 0 {
                    let usedDelta = userDelta + sysDelta + niceDelta
                    cpuFraction = min(max(usedDelta / totalDelta, 0), 1)
                    userPercent = Int((userDelta / totalDelta * 100).rounded())
                    sysPercent = Int((sysDelta / totalDelta * 100).rounded())
                }
            }
            previousInfo = cpuInfo
        }

        let primaryWindow = LimitWindow(
            id: "cpu-usage",
            label: L10n.t("CPU Load"),
            usedFraction: cpuFraction,
            detail: "User: \(userPercent)% · System: \(sysPercent)%"
        )

        let userWindow = LimitWindow(
            id: "cpu-user",
            label: L10n.t("User"),
            usedText: "\(userPercent)%"
        )

        let sysWindow = LimitWindow(
            id: "cpu-system",
            label: L10n.t("System"),
            usedText: "\(sysPercent)%"
        )

        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        let coresWindow = LimitWindow(
            id: "cpu-cores",
            label: L10n.t("Cores"),
            usedText: "\(coreCount)"
        )

        // System Load Averages (1m, 5m, 15m)
        var loadavg = [Double](repeating: 0.0, count: 3)
        let loadCount = getloadavg(&loadavg, 3)
        let loadText: String
        if loadCount > 0 {
            loadText = String(format: "%.2f, %.2f, %.2f", loadavg[0], loadavg[1], loadavg[2])
        } else {
            loadText = L10n.t("Unavailable")
        }

        let loadWindow = LimitWindow(
            id: "cpu-loadavg",
            label: L10n.t("Load Average (1/5/15m)"),
            usedText: loadText
        )

        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: [primaryWindow, userWindow, sysWindow, coresWindow, loadWindow],
            headlineID: "cpu-usage"
        )
    }
}

// MARK: - GPU Provider
actor GPUProvider: UsageProvider {
    nonisolated let id = "system-gpu"
    nonisolated let displayName = "GPU"
    nonisolated let glyph = ProviderGlyph.gpu
    nonisolated let signInRoute = SignInRoute.guidance(L10n.t("System Activity Monitor"))

    struct Reading {
        var utilization: Double?
        var rendererUtilization: Double?
        var inUseBytes: UInt64?
        var allocatedBytes: UInt64?

        init(utilization: Double? = nil,
             rendererUtilization: Double? = nil,
             inUseBytes: UInt64? = nil,
             allocatedBytes: UInt64? = nil) {
            self.utilization = utilization
            self.rendererUtilization = rendererUtilization
            self.inUseBytes = inUseBytes
            self.allocatedBytes = allocatedBytes
        }
    }

    init() {}

    nonisolated func account() -> ProviderAccount? {
        let name = MTLCreateSystemDefaultDevice()?.name ?? "GPU"
        return ProviderAccount(label: name, plan: nil, source: "Metal", manageURL: nil)
    }

    func signOut() async {}
    nonisolated func forgetCachedCredential() {}

    /// The accelerator's own PerformanceStatistics dictionary. Apple Silicon
    /// publishes it under IOAccelerator; Intel Macs use the same keys.
    static func read() -> Reading {
        var reading = Reading()
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else {
            return reading
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let statistics = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] else { continue }

            reading.utilization = fraction(statistics["Device Utilization %"])
            reading.rendererUtilization = fraction(statistics["Renderer Utilization %"])
            reading.inUseBytes = byteCount(statistics["In use system memory"])
            reading.allocatedBytes = byteCount(statistics["Alloc system memory"])
            break
        }
        return reading
    }

    static func fraction(_ value: Any?) -> Double? {
        guard let number = number(value) else { return nil }
        let fraction = number > 1 ? number / 100 : number
        return min(max(fraction, 0), 1)
    }

    static func byteCount(_ value: Any?) -> UInt64? {
        guard let number = number(value), number >= 0 else { return nil }
        return UInt64(number)
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as NSNumber: return value.doubleValue
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as Int64: return Double(value)
        case let value as UInt64: return Double(value)
        default: return nil
        }
    }

    private static func bytesText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let reading = Self.read()
        let device = MTLCreateSystemDefaultDevice()
        let budget = device?.recommendedMaxWorkingSetSize

        let load = reading.utilization ?? reading.rendererUtilization ?? 0
        let loadPercent = Int((load * 100).rounded())
        let rendererPercent = Int(((reading.rendererUtilization ?? load) * 100).rounded())

        var windows: [LimitWindow] = [
            LimitWindow(
                id: "gpu-usage",
                label: L10n.t("GPU Load"),
                usedFraction: load,
                usedText: "\(loadPercent)%",
                detail: "\(L10n.t("Renderer")): \(rendererPercent)%"
            )
        ]

        if let inUse = reading.inUseBytes {
            let fraction = budget.flatMap { $0 > 0 ? min(Double(inUse) / Double($0), 1) : nil }
            windows.append(LimitWindow(
                id: "gpu-memory",
                label: L10n.t("GPU Memory"),
                usedFraction: fraction,
                usedText: Self.bytesText(inUse),
                detail: budget.map { "\(Self.bytesText(inUse)) / \(Self.bytesText($0))" }
            ))
        }

        if let allocated = reading.allocatedBytes {
            windows.append(LimitWindow(
                id: "gpu-allocated",
                label: L10n.t("Allocated Memory"),
                usedText: Self.bytesText(allocated)
            ))
        }

        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: windows,
            headlineID: "gpu-usage"
        )
    }
}

// MARK: - Disk Provider
actor DiskProvider: UsageProvider {
    nonisolated let id = "system-storage"
    nonisolated let displayName = "Disk"
    nonisolated let glyph = ProviderGlyph.disk
    nonisolated let signInRoute = SignInRoute.guidance(L10n.t("System Activity Monitor"))

    struct Volume {
        var name: String
        var total: UInt64
        var free: UInt64
        var isRoot: Bool
        var mountBSD: String?

        init(name: String, total: UInt64, free: UInt64, isRoot: Bool, mountBSD: String? = nil) {
            self.name = name
            self.total = total
            self.free = free
            self.isRoot = isRoot
            self.mountBSD = mountBSD
        }
    }

    struct DiskSample {
        var bsd: String
        var name: String
        var read: UInt64
        var write: UInt64
        var slices: Set<String>

        init(bsd: String, name: String, read: UInt64, write: UInt64, slices: Set<String>) {
            self.bsd = bsd
            self.name = name
            self.read = read
            self.write = write
            self.slices = slices
        }
    }

    private var lastDiskCounters: [String: (read: UInt64, write: UInt64)] = [:]
    private var lastReadBytes: UInt64 = 0
    private var lastWriteBytes: UInt64 = 0
    private var lastSample: Date?

    init() {}

    nonisolated func account() -> ProviderAccount? {
        ProviderAccount(label: "\(Self.volumes().count) Volumes", plan: nil, source: "macOS", manageURL: nil)
    }

    func signOut() async {}
    nonisolated func forgetCachedCredential() {}

    // MARK: Disk capacity and mounted volumes

    static func capacity() -> (total: UInt64, free: UInt64) {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else {
            return (0, 0)
        }
        let total = UInt64(max(values.volumeTotalCapacity ?? 0, 0))
        let important = values.volumeAvailableCapacityForImportantUsage ?? 0
        let plain = Int64(values.volumeAvailableCapacity ?? 0)
        return (total, UInt64(max(max(important, plain), 0)))
    }

    static func volumes() -> [Volume] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsRootFileSystemKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) else { return [] }

        var seen = Set<String>()
        var volumes: [Volume] = []
        for url in urls {
            // The Data volume is the same storage as the root volume, and the
            // other synthetic volumes are not something a user can free space on.
            if url.path.hasPrefix("/System/Volumes/") { continue }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            let name = values.volumeName ?? url.lastPathComponent
            let total = UInt64(max(values.volumeTotalCapacity ?? 0, 0))
            guard total > 0, seen.insert(name).inserted else { continue }
            let important = values.volumeAvailableCapacityForImportantUsage ?? 0
            let plain = Int64(values.volumeAvailableCapacity ?? 0)
            let free = UInt64(max(max(important, plain), 0))
            volumes.append(Volume(
                name: name,
                total: total,
                free: free,
                isRoot: url.path == "/",
                mountBSD: mountBSD(of: url.path)
            ))
        }
        return volumes.sorted {
            if $0.isRoot != $1.isRoot { return $0.isRoot }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func mountBSD(of path: String) -> String? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        let device = withUnsafePointer(to: &info.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        return device.hasPrefix("/dev/") ? String(device.dropFirst(5)) : device
    }

    // MARK: IOKit block-storage counters

    static func wholeMedia(of driver: io_service_t) -> (bsd: String, name: String)? {
        guard let media = findWholeMedia(driver) else { return nil }
        defer { IOObjectRelease(media) }
        guard let bsd = property(of: media, "BSD Name") as? String else { return nil }
        let product = property(of: media, "Product Name") as? String
        return (bsd, product ?? bsd)
    }

    private static func findWholeMedia(_ entry: io_service_t) -> io_service_t? {
        if (property(of: entry, "Whole") as? Bool) == true,
           property(of: entry, "BSD Name") as? String != nil {
            return entry
        }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator), child != 0 {
            if let found = findWholeMedia(child) {
                // A direct child is the returned object itself; the caller owns
                // it and releases it after reading. Only a deeper match leaves
                // the child to be released here.
                if found != child { IOObjectRelease(child) }
                return found
            }
            IOObjectRelease(child)
        }
        return nil
    }

    static func collectSlices(of entry: io_service_t, into slices: inout Set<String>) {
        if let bsd = property(of: entry, "BSD Name") as? String {
            slices.insert(bsd)
        }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator), child != 0 {
            collectSlices(of: child, into: &slices)
            IOObjectRelease(child)
        }
    }

    private static func property(of entry: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    static func diskCounters() -> [DiskSample] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var samples: [DiskSample] = []
        while case let driver = IOIteratorNext(iterator), driver != 0 {
            defer { IOObjectRelease(driver) }
            guard let statistics = property(of: driver, "Statistics") as? [String: Any],
                  let whole = wholeMedia(of: driver) else { continue }

            var slices = Set<String>()
            collectSlices(of: driver, into: &slices)
            slices.remove(whole.bsd)

            samples.append(DiskSample(
                bsd: whole.bsd,
                name: whole.name,
                read: (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0,
                write: (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0,
                slices: slices
            ))
        }
        return samples
    }

    static func ioCounters() -> (read: UInt64, write: UInt64) {
        diskCounters().reduce((0, 0)) { totals, sample in
            (totals.0 + sample.read, totals.1 + sample.write)
        }
    }

    // MARK: Display

    private static func bytesText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func rateText(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1024 { return "0 KB/s" }
        if bytesPerSecond < 1_048_576 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1024)
        }
        if bytesPerSecond < 1_073_741_824 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576)
        }
        return String(format: "%.1f GB/s", bytesPerSecond / 1_073_741_824)
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let now = Date()
        let samples = Self.diskCounters()
        let totalRead = samples.reduce(0) { $0 + $1.read }
        let totalWrite = samples.reduce(0) { $0 + $1.write }
        let elapsed = lastSample.map { now.timeIntervalSince($0) } ?? 0

        var readRate = 0.0
        var writeRate = 0.0
        if elapsed > 0 {
            if totalRead >= lastReadBytes {
                readRate = Double(totalRead - lastReadBytes) / elapsed
            }
            if totalWrite >= lastWriteBytes {
                writeRate = Double(totalWrite - lastWriteBytes) / elapsed
            }
        }

        var counters: [String: (read: UInt64, write: UInt64)] = [:]
        for sample in samples {
            counters[sample.bsd] = (sample.read, sample.write)
        }
        lastDiskCounters = counters
        lastReadBytes = totalRead
        lastWriteBytes = totalWrite
        lastSample = now

        let capacity = Self.capacity()
        let volumes = Self.volumes()
        let used = capacity.total > capacity.free ? capacity.total - capacity.free : 0
        let usedFraction = capacity.total > 0 ? Double(used) / Double(capacity.total) : nil

        var windows: [LimitWindow] = [
            LimitWindow(
                id: "disk-usage",
                label: L10n.t("Disk Space"),
                usedFraction: usedFraction,
                usedText: "\(Self.bytesText(capacity.free)) " + L10n.t("free"),
                detail: "\(Self.bytesText(used)) " + L10n.t("of") + " \(Self.bytesText(capacity.total)) " + L10n.t("used")
            ),
            LimitWindow(
                id: "disk-read",
                label: L10n.t("Read"),
                usedText: Self.rateText(readRate)
            ),
            LimitWindow(
                id: "disk-write",
                label: L10n.t("Write"),
                usedText: Self.rateText(writeRate)
            ),
            LimitWindow(
                id: "disk-rate",
                label: L10n.t("Disk Activity"),
                usedText: "R \(Self.rateText(readRate)) · W \(Self.rateText(writeRate))",
                detail: samples.isEmpty ? nil : "\(samples.count) " + L10n.t("drives")
            )
        ]

        for volume in volumes {
            let free = min(volume.free, volume.total)
            let used = volume.total - free
            windows.append(LimitWindow(
                id: "disk-volume-\(volume.name)",
                label: volume.name,
                usedFraction: volume.total > 0 ? Double(used) / Double(volume.total) : nil,
                usedText: "\(Self.bytesText(free)) " + L10n.t("free"),
                detail: "\(Self.bytesText(used)) " + L10n.t("of") + " \(Self.bytesText(volume.total))"
            ))
        }

        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: windows,
            headlineID: "disk-usage"
        )
    }
}

// MARK: - Thermals Provider
actor ThermalsProvider: UsageProvider {
    nonisolated let id = "system-thermals"
    nonisolated let displayName = "Thermals"
    nonisolated let glyph = ProviderGlyph.thermals
    nonisolated let signInRoute = SignInRoute.guidance(L10n.t("System Activity Monitor"))

    init() {}

    nonisolated func account() -> ProviderAccount? {
        return ProviderAccount(label: "Thermal State", plan: nil, source: "macOS", manageURL: nil)
    }

    func signOut() async {}
    nonisolated func forgetCachedCredential() {}

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let thermalState = ProcessInfo.processInfo.thermalState
        let fraction: Double
        let labelText: String

        switch thermalState {
        case .nominal:
            fraction = 0.0
            labelText = L10n.t("Nominal")
        case .fair:
            fraction = 0.33
            labelText = L10n.t("Fair")
        case .serious:
            fraction = 0.67
            labelText = L10n.t("Serious")
        case .critical:
            fraction = 1.0
            labelText = L10n.t("Critical")
        @unknown default:
            fraction = 0.0
            labelText = L10n.t("Normal")
        }

        let primaryWindow = LimitWindow(
            id: "thermals-state",
            label: L10n.t("Thermal Pressure"),
            usedFraction: fraction,
            usedText: labelText,
            detail: labelText
        )

        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: [primaryWindow],
            headlineID: "thermals-state"
        )
    }
}

// MARK: - Network Provider
actor NetworkProvider: UsageProvider {
    nonisolated let id = "system-network"
    nonisolated let displayName = "Network"
    nonisolated let glyph = ProviderGlyph.network
    nonisolated let signInRoute = SignInRoute.guidance(L10n.t("System Activity Monitor"))

    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var lastTime: Date?

    init() {}

    nonisolated func account() -> ProviderAccount? {
        return ProviderAccount(label: "Network Activity", plan: nil, source: "macOS", manageURL: nil)
    }

    func signOut() async {}
    nonisolated func forgetCachedCredential() {}

    func fetchSnapshot() async throws -> ProviderSnapshot {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            throw UsageProviderError.badResponse(status: 0)
        }
        defer { freeifaddrs(ifaddr) }

        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0

        var ptr = UnsafeMutablePointer<ifaddrs>? (firstAddr)
        while ptr != nil {
            guard let interface = ptr?.pointee else { break }
            let name = String(cString: interface.ifa_name)
            // Exclude loopback
            if !name.hasPrefix("lo"), let data = interface.ifa_data {
                let networkData = data.pointing(to: if_data.self)
                bytesIn += UInt64(networkData.pointee.ifi_ibytes)
                bytesOut += UInt64(networkData.pointee.ifi_obytes)
            }
            ptr = interface.ifa_next
        }

        let now = Date()
        var downloadRate: Double = 0
        var uploadRate: Double = 0

        if let prevTime = lastTime {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                if bytesIn >= lastBytesIn {
                    downloadRate = Double(bytesIn - lastBytesIn) / elapsed
                }
                if bytesOut >= lastBytesOut {
                    uploadRate = Double(bytesOut - lastBytesOut) / elapsed
                }
            }
        }

        lastBytesIn = bytesIn
        lastBytesOut = bytesOut
        lastTime = now

        let dlText = formatRate(downloadRate)
        let ulText = formatRate(uploadRate)

        // Fraction based on soft peak scale of 10 MB/s (10,485,760 bytes/sec)
        let networkFraction = min(max(downloadRate / 10_485_760.0, 0), 1)

        let primaryWindow = LimitWindow(
            id: "network-speed",
            label: L10n.t("Network Speed"),
            usedFraction: networkFraction,
            usedText: "↓ \(dlText)",
            detail: "↓ \(dlText)  ↑ \(ulText)"
        )

        let downloadWindow = LimitWindow(
            id: "network-download",
            label: L10n.t("Download Speed"),
            usedText: dlText
        )

        let uploadWindow = LimitWindow(
            id: "network-upload",
            label: L10n.t("Upload Speed"),
            usedText: ulText
        )

        let totalInText = formatBytes(bytesIn)
        let totalOutText = formatBytes(bytesOut)

        let totalInWindow = LimitWindow(
            id: "network-total-in",
            label: L10n.t("Total Received"),
            usedText: totalInText
        )

        let totalOutWindow = LimitWindow(
            id: "network-total-out",
            label: L10n.t("Total Sent"),
            usedText: totalOutText
        )

        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: [primaryWindow, downloadWindow, uploadWindow, totalInWindow, totalOutWindow],
            headlineID: "network-speed"
        )
    }

    private func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 {
            return "0 KB/s"
        } else if bytesPerSec < 1_048_576 {
            return "\(Int((bytesPerSec / 1024.0).rounded())) KB/s"
        } else {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576.0)
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        if b < 1024 {
            return "\(bytes) B"
        } else if b < 1_048_576 {
            return String(format: "%.1f KB", b / 1024.0)
        } else if b < 1_073_741_824 {
            return String(format: "%.1f MB", b / 1_048_576.0)
        } else {
            return String(format: "%.2f GB", b / 1_073_741_824.0)
        }
    }
}

// Helper extension to safely bind memory
private extension UnsafeMutableRawPointer {
    func pointing<T>(to type: T.Type) -> UnsafeMutablePointer<T> {
        return self.assumingMemoryBound(to: type)
    }
}

// MARK: - Energy Provider
actor EnergyProvider: UsageProvider {
    nonisolated let id = "system-energy"
    nonisolated let displayName = "Energy"
    nonisolated let glyph = ProviderGlyph.energy
    nonisolated let signInRoute = SignInRoute.guidance(L10n.t("System Activity Monitor"))

    init() {}

    nonisolated func account() -> ProviderAccount? {
        let machine = MachineIdentity.current
        let label = machine.isPortable
            ? "\(machine.displayName) · Battery & Power"
            : "\(machine.displayName) · Power"
        return ProviderAccount(label: label, plan: nil, source: "macOS", manageURL: nil)
    }

    func signOut() async {}
    nonisolated func forgetCachedCredential() {}

    nonisolated static let assumedPeakWatts: Double = 96

    /// AppleSmartBattery carries the adapter, amperage and power telemetry that
    /// IOPS does not expose. A desktop with no battery simply returns nil.
    nonisolated static func smartBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
            return nil
        }
        return properties?.takeRetainedValue() as? [String: Any]
    }

    nonisolated static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as NSNumber: return value.doubleValue
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as Int64: return Double(value)
        case let value as UInt64: return Double(value)
        default: return nil
        }
    }

    /// The adapter's rated watts, when macOS reports them.
    nonisolated static func adapterWatts(from properties: [String: Any]?) -> Double? {
        guard let properties else { return nil }
        let details = properties["AdapterDetails"] as? [String: Any]
        return number(details?["Watts"]) ?? number(properties["AdapterWatts"])
    }

    /// The machine's ceiling. Without an adapter rating, the old app used a
    /// deliberately conservative fixed figure rather than inventing a peak.
    nonisolated static func peakWatts(from battery: [String: Any]?) -> Double {
        guard let watts = adapterWatts(from: battery), watts > 0 else {
            return assumedPeakWatts
        }
        return watts
    }

    /// Prefer the system power telemetry in milliwatts. On Intel Macs, fall
    /// back to the battery's voltage and instantaneous amperage.
    nonisolated static func powerDrawWatts(from properties: [String: Any]) -> Double? {
        if let telemetry = properties["PowerTelemetryData"] as? [String: Any] {
            for key in ["SystemPowerIn", "SystemLoad", "SystemPowerOut", "AdapterPower"] {
                if let milliwatts = number(telemetry[key]), milliwatts > 0 {
                    return milliwatts / 1000
                }
            }
        }

        guard let millivolts = number(properties["Voltage"]),
              let milliamps = number(properties["InstantAmperage"] ?? properties["Amperage"]),
              millivolts > 0, milliamps != 0 else { return nil }
        return abs(millivolts * milliamps) / 1_000_000
    }

    /// Watt-hours taken out of the pack since it was last full: the raw
    /// capacities are in mAh, the voltage in mV.
    nonisolated static func wattHoursConsumed(from properties: [String: Any]) -> Double? {
        guard let full = number(properties["AppleRawMaxCapacity"]),
              let current = number(properties["AppleRawCurrentCapacity"]),
              let millivolts = number(properties["Voltage"]),
              full > current, millivolts > 0 else { return nil }
        return (full - current) * millivolts / 1_000_000
    }

    nonisolated static func wattsText(_ watts: Double) -> String {
        String(format: "%.1f W", watts)
    }

    nonisolated static func wattHoursText(_ wattHours: Double) -> String {
        String(format: "%.1f Wh", wattHours)
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        var batteryLevel: Double = 1.0
        var isCharging = false
        var powerSource = L10n.t("AC Power")
        var hasBattery = false
        var timeRemainingMinutes: Int? = nil
        var isCharged = false

        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                    // A UPS is a power source but not a battery this Mac carries.
                    guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                    hasBattery = true
                    if let current = description[kIOPSCurrentCapacityKey] as? Int,
                       let maxCapacity = description[kIOPSMaxCapacityKey] as? Int, maxCapacity > 0 {
                        batteryLevel = min(max(Double(current) / Double(maxCapacity), 0), 1)
                    }
                    if let state = description[kIOPSPowerSourceStateKey] as? String {
                        if state == kIOPSACPowerValue {
                            powerSource = L10n.t("AC Power")
                        } else {
                            powerSource = L10n.t("On Battery")
                        }
                    }
                    if let charging = description[kIOPSIsChargingKey] as? Bool {
                        isCharging = charging
                    }
                    if let charged = description[kIOPSIsChargedKey] as? Bool {
                        isCharged = charged
                    }
                    if let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int, timeToEmpty > 0 {
                        timeRemainingMinutes = timeToEmpty
                    } else if let timeToFull = description[kIOPSTimeToFullChargeKey] as? Int, timeToFull > 0 {
                        timeRemainingMinutes = timeToFull
                    }
                }
            }
        }

        let battery = Self.smartBatteryProperties()
        let powerDraw = battery.flatMap { Self.powerDrawWatts(from: $0) }
        let peak = Self.peakWatts(from: battery)
        let adapter = battery.flatMap { Self.adapterWatts(from: $0) }
        let consumed = battery.flatMap { Self.wattHoursConsumed(from: $0) }

        let percent = Int((batteryLevel * 100).rounded())
        let statusString: String
        if !hasBattery {
            statusString = L10n.t("AC Power")
        } else if isCharged {
            statusString = "\(percent)% · " + L10n.t("Fully Charged")
        } else if isCharging {
            if let mins = timeRemainingMinutes {
                let hrs = mins / 60
                let remMins = mins % 60
                let timeStr = hrs > 0 ? "\(hrs)h \(remMins)m" : "\(remMins)m"
                statusString = "\(percent)% · \(timeStr) until full"
            } else {
                statusString = "\(percent)% · " + L10n.t("Charging")
            }
        } else {
            if let mins = timeRemainingMinutes {
                let hrs = mins / 60
                let remMins = mins % 60
                let timeStr = hrs > 0 ? "\(hrs)h \(remMins)m" : "\(remMins)m"
                statusString = "\(percent)% · \(timeStr) remaining"
            } else {
                statusString = "\(percent)% · " + powerSource
            }
        }

        let batteryBand: UsageBand
        if batteryLevel >= 0.50 {
            batteryBand = .ample
        } else if batteryLevel >= 0.20 {
            batteryBand = .watch
        } else {
            batteryBand = .critical
        }

        let batteryWindow = LimitWindow(
            id: "energy-status",
            label: L10n.t("Battery Level"),
            usedFraction: batteryLevel,
            usedText: "\(percent)%",
            detail: statusString,
            bandOverride: batteryBand
        )

        let powerSourceWindow = LimitWindow(
            id: "energy-source",
            label: L10n.t("Power Source"),
            usedText: powerSource
        )

        let chargingWindow = LimitWindow(
            id: "energy-charging",
            label: L10n.t("State"),
            usedText: isCharging ? L10n.t("Charging") : (hasBattery ? (isCharged ? L10n.t("Fully Charged") : L10n.t("Discharging")) : L10n.t("Connected"))
        )

        let drawWindow = powerDraw.map { draw in
            LimitWindow(
                id: "energy-draw",
                label: L10n.t("Power Draw"),
                usedFraction: min(max(draw / peak, 0), 1),
                usedText: Self.wattsText(draw),
                detail: "\(Self.wattsText(draw)) " + L10n.t("of") + " \(Self.wattsText(peak)) — " + L10n.t("what this Mac can draw at full tilt")
            )
        }

        // A Mac without a battery has no battery row to show. It leads with
        // live power draw instead, which is the reading its owner can act on.
        var windows: [LimitWindow] = []
        if hasBattery {
            windows.append(batteryWindow)
        } else if let drawWindow {
            windows.append(drawWindow)
        }
        windows.append(powerSourceWindow)
        if hasBattery {
            windows.append(chargingWindow)
        }
        if hasBattery, let drawWindow {
            windows.append(drawWindow)
        }

        if let adapter {
            windows.append(LimitWindow(
                id: "energy-adapter",
                label: L10n.t("Adapter"),
                usedText: Self.wattsText(adapter)
            ))
        }

        if let consumed {
            windows.append(LimitWindow(
                id: "energy-consumed",
                label: L10n.t("Energy Used"),
                usedText: Self.wattHoursText(consumed),
                detail: L10n.t("Since last full charge")
            ))
        }

        if hasBattery, let mins = timeRemainingMinutes {
            let hrs = mins / 60
            let remMins = mins % 60
            let formattedTime = hrs > 0 ? "\(hrs)h \(remMins)m" : "\(remMins)m"
            let timeLabel = isCharging ? L10n.t("Time to Full") : L10n.t("Time Remaining")
            let timeWindow = LimitWindow(
                id: "energy-time",
                label: timeLabel,
                usedText: formattedTime
            )
            windows.append(timeWindow)
        }

        let headlineID: String
        if hasBattery {
            headlineID = "energy-status"
        } else if powerDraw != nil {
            headlineID = "energy-draw"
        } else {
            headlineID = "energy-source"
        }

        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: windows,
            headlineID: headlineID
        )
    }
}

// MARK: - SMC Helper for Fan Speed
private struct SMCKeyData {
    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
    }
    struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = LimitData()
    var keyInfo = KeyInfo()
    var padding: UInt8 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0)
}

private enum SMCSpeedReader {
    private static func fourCharKey(_ key: String) -> UInt32 {
        var result: UInt32 = 0
        for char in key.utf8 {
            result = (result << 8) | UInt32(char)
        }
        return result
    }

    static func getFanRPM() -> Int {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
            return 0
        }
        defer { IOServiceClose(conn) }

        func readKey(_ keyStr: String) -> Double? {
            let keyNum = fourCharKey(keyStr)
            var input = SMCKeyData()
            var output = SMCKeyData()
            input.key = keyNum
            input.data8 = 9 // kSMCGetKeyInfo

            let inputSize = MemoryLayout<SMCKeyData>.stride
            var outputSize = MemoryLayout<SMCKeyData>.stride

            let status = IOConnectCallStructMethod(conn, 2, &input, inputSize, &output, &outputSize)
            guard status == kIOReturnSuccess else { return nil }

            input.keyInfo = output.keyInfo
            input.data8 = 5 // kSMCReadKey

            let readStatus = IOConnectCallStructMethod(conn, 2, &input, inputSize, &output, &outputSize)
            guard readStatus == kIOReturnSuccess else { return nil }

            let bytes = output.bytes
            let size = output.keyInfo.dataSize
            let type = output.keyInfo.dataType

            if type == 0x666C7420 && size == 4 { // flt
                var floatVal: Float = 0
                var rawBytes = (bytes.0, bytes.1, bytes.2, bytes.3)
                withUnsafeBytes(of: &rawBytes) { ptr in
                    if let base = ptr.baseAddress {
                        floatVal = base.assumingMemoryBound(to: Float.self).pointee
                    }
                }
                return Double(floatVal)
            } else if size >= 2 {
                let val = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
                if type == 0x66706532 { // fpe2
                    return Double(val) / 4.0
                }
                return Double(val)
            }
            return nil
        }

        let fan0 = readKey("F0Ac") ?? 0
        let fan1 = readKey("F1Ac") ?? 0
        let maxFan = max(fan0, fan1)
        return Int(maxFan.rounded())
    }
}

// MARK: - Fan Speed Provider
actor FanProvider: UsageProvider {
    nonisolated let id = "system-fan"
    nonisolated let displayName = "Fan Speed"
    nonisolated let glyph = ProviderGlyph.fan
    nonisolated let signInRoute = SignInRoute.guidance(L10n.t("System Activity Monitor"))

    init() {}

    nonisolated func account() -> ProviderAccount? {
        return ProviderAccount(label: "Fan Speed RPM", plan: nil, source: "macOS", manageURL: nil)
    }

    func signOut() async {}
    nonisolated func forgetCachedCredential() {}

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let rpm = SMCSpeedReader.getFanRPM()
        let maxExpectedRPM = 6000.0
        let fraction = min(max(Double(rpm) / maxExpectedRPM, 0), 1)

        let labelText = rpm > 0 ? "\(rpm) RPM" : L10n.t("0 RPM")

        let primaryWindow = LimitWindow(
            id: "fan-speed",
            label: L10n.t("Fan Speed"),
            usedFraction: fraction,
            usedText: labelText,
            detail: labelText
        )

        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: [primaryWindow],
            headlineID: "fan-speed"
        )
    }
}

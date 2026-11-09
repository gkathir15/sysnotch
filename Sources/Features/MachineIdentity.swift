import Foundation
import IOKit.ps

/// What this Mac is, in the terms the system panes need: the hardware family
/// (so a MacBook can show battery and a Mac mini cannot), the chip, and the
/// amount of memory. Read once and cached — the answer cannot change while the
/// app is running.
struct MachineIdentity: Sendable {
    enum Family: String, Codable, Sendable {
        case macBookAir
        case macBookPro
        case macMini
        case imac
        case macStudio
        case macPro
        case mac

        var label: String {
            switch self {
            case .macBookAir: return "MacBook Air"
            case .macBookPro: return "MacBook Pro"
            case .macMini:    return "Mac mini"
            case .imac:       return "iMac"
            case .macStudio:  return "Mac Studio"
            case .macPro:     return "Mac Pro"
            case .mac:        return "Mac"
            }
        }

        var isPortable: Bool {
            switch self {
            case .macBookAir, .macBookPro: return true
            case .macMini, .imac, .macStudio, .macPro, .mac: return false
            }
        }

        /// The family named by a Bonjour service, reverse-DNS name, or a
        /// `system_profiler` machine name. Longest phrases are checked before
        /// the generic "Mac" so "MacBook Pro" does not become "Mac".
        static func named(_ text: String) -> Family? {
            let lower = text.lowercased()
            if lower.contains("macbook air") || lower.contains("macbookair") { return .macBookAir }
            if lower.contains("macbook pro") || lower.contains("macbookpro") { return .macBookPro }
            if lower.contains("macbook") { return .macBookPro }
            if lower.contains("mac mini") || lower.contains("macmini") { return .macMini }
            if lower.contains("mac studio") || lower.contains("macstudio") { return .macStudio }
            if lower.contains("imac") { return .imac }
            if lower.contains("mac pro") || lower.contains("macpro") { return .macPro }
            if lower.contains("mac") { return .mac }
            return nil
        }
    }

    let hardwareModel: String
    let family: Family
    let chip: String
    let coreCount: Int
    let memoryBytes: UInt64
    let hasBattery: Bool
    private let marketingName: String?

    /// The name shown to people, falling back to the family when macOS does not
    /// publish a marketing name.
    var displayName: String { marketingName ?? family.label }

    var memoryText: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    var isPortable: Bool { hasBattery || family.isPortable }

    static let current = MachineIdentity()

    private init() {
        let model = Self.sysctlString("hw.model") ?? ""
        let profile = Self.hardwareProfile()
        hardwareModel = profile?.model ?? model
        chip = Self.sysctlString("machdep.cpu.brand_string")
            ?? profile?.chip
            ?? "Apple Silicon"
        coreCount = ProcessInfo.processInfo.activeProcessorCount
        memoryBytes = ProcessInfo.processInfo.physicalMemory
        hasBattery = Self.internalBatteryPresent()
        family = Self.family(hardwareModel: model, machineName: profile?.name)
        marketingName = profile?.name
    }

    private static func family(hardwareModel: String, machineName: String?) -> Family {
        if let named = Family.named(machineName ?? "") { return named }
        if let named = Family.named(hardwareModel) { return named }
        return .mac
    }

    /// True only for a built-in battery. A desktop with a UPS on the power
    /// source list is still a desktop.
    private static func internalBatteryPresent() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                return true
            }
        }
        return false
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private struct HardwareProfile {
        let name: String?
        let model: String?
        let chip: String?
    }

    /// `system_profiler` is the only public source that turns a modern
    /// identifier such as `Mac18,5` into "Mac mini"; `sysctl hw.model` alone
    /// cannot tell a mini from a MacBook. It runs once, only on this struct's
    /// first use.
    private static func hardwareProfile() -> HardwareProfile? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPHardwareDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        struct Report: Decodable {
            struct Entry: Decodable {
                let machine_name: String?
                let machine_model: String?
                let chip_type: String?
            }
            let SPHardwareDataType: [Entry]?
        }
        guard let report = try? JSONDecoder().decode(Report.self, from: data),
              let entry = report.SPHardwareDataType?.first else { return nil }
        return HardwareProfile(name: entry.machine_name,
                               model: entry.machine_model,
                               chip: entry.chip_type)
    }
}

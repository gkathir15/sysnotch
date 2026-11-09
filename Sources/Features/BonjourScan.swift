import Darwin
import Foundation

/// A Bonjour service resolved back to the IPv4 address it answered on.
struct BonjourService: Sendable {
    let name: String
    let type: String
    let hostName: String?
    let model: String?
    let txt: [String: String]
    let addresses: [String]

    /// The most specific human string this advertisement carries, for matching
    /// a machine family or a device kind.
    var searchText: String {
        ([name, hostName, model] + Array(txt.values)).compactMap { $0 }.joined(separator: " ")
    }
}

/// Browses the local Bonjour domains for the service types Macs and the common
/// home devices publish, then resolves each one to an address. This is what
/// gives the Network pane friendly names such as "Guru's Mac mini" instead of
/// only reverse DNS.
enum BonjourScan {
    static let serviceTypes = [
        "_companion-link._tcp.",
        "_workstation._tcp.",
        "_ssh._tcp.",
        "_smb._tcp.",
        "_airplay._tcp.",
        "_raop._tcp.",
        "_ipp._tcp.",
        "_printer._tcp.",
        "_googlecast._tcp.",
        "_hap._tcp.",
        "_sonos._tcp.",
        "_device-info._tcp."
    ]

    /// Best name for a device when several services answer for it. Macs publish
    /// Companion Link and a workstation record; printers publish IPP and
    /// printer records; the first is the more descriptive.
    static let typePriority = [
        "_companion-link._tcp": 0,
        "_workstation._tcp": 1,
        "_smb._tcp": 2,
        "_ssh._tcp": 3,
        "_airplay._tcp": 4,
        "_raop._tcp": 5,
        "_device-info._tcp": 6,
        "_ipp._tcp": 7,
        "_printer._tcp": 8,
        "_googlecast._tcp": 9,
        "_sonos._tcp": 10,
        "_hap._tcp": 11
    ]

    static func run(timeout: TimeInterval = 1.6) -> [BonjourService] {
        let scanner = Scanner()
        return scanner.run(timeout: timeout)
    }

    private final class Scanner: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
        /// One browser per type: a single browser accepts only one search and
        /// answers every later `searchForServices` with kCFNetServicesErrorBadArgument.
        private var browsers: [NetServiceBrowser] = []
        private var services: [NetService] = []
        private var resolved: [String: BonjourService] = [:]
        private let lock = NSLock()

        func run(timeout: TimeInterval) -> [BonjourService] {
            for type in BonjourScan.serviceTypes {
                let browser = NetServiceBrowser()
                browser.delegate = self
                browsers.append(browser)
                browser.searchForServices(ofType: type, inDomain: "local.")
            }

            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                RunLoop.current.run(mode: .default,
                                    before: min(deadline, Date().addingTimeInterval(0.1)))
            }
            for browser in browsers { browser.stop() }
            for service in services { service.stop() }

            lock.lock()
            defer { lock.unlock() }
            return resolved.values.sorted {
                let left = BonjourScan.typePriority[$0.type] ?? 99
                let right = BonjourScan.typePriority[$1.type] ?? 99
                return left == right ? $0.name < $1.name : left < right
            }
        }

        func netServiceBrowser(_ browser: NetServiceBrowser,
                               didFind service: NetService,
                               moreComing: Bool) {
            service.delegate = self
            services.append(service)
            // `resolve` does not schedule the service itself; without this it
            // posts no callback even while the run loop is turning.
            service.schedule(in: .current, forMode: .default)
            service.resolve(withTimeout: 0.8)
        }

        func netServiceBrowser(_ browser: NetServiceBrowser,
                               didNotSearch errorDict: [String: NSNumber]) {}

        func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {}

        func netServiceDidResolveAddress(_ sender: NetService) {
            let addresses = (sender.addresses ?? []).flatMap(Self.ipv4Addresses)
            guard !addresses.isEmpty else { return }

            let txt = sender.txtRecordData().map { data in
                NetService.dictionary(fromTXTRecord: data).mapValues {
                    String(decoding: $0, as: UTF8.self)
                }
            } ?? [:]

            let model = ["model", "md", "am", "rpMd", "modelName", "ty"]
                .compactMap { txt[$0] }
                .first { !$0.isEmpty && $0.lowercased() != "1" }

            let type = sender.type.hasSuffix(".")
                ? String(sender.type.dropLast())
                : sender.type
            let host = sender.hostName?
                .replacingOccurrences(of: ".local.", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))

            let service = BonjourService(
                name: sender.name,
                type: type,
                hostName: host?.isEmpty == false ? host : nil,
                model: model,
                txt: txt,
                addresses: addresses
            )

            lock.lock()
            for address in addresses {
                let existing = resolved[address]
                if existing == nil || (BonjourScan.typePriority[type] ?? 99)
                    < (BonjourScan.typePriority[existing?.type ?? ""] ?? 99) {
                    resolved[address] = service
                }
            }
            lock.unlock()
        }

        private static func ipv4Addresses(_ data: Data) -> [String] {
            data.withUnsafeBytes { raw -> [String] in
                guard let base = raw.baseAddress else { return [] }
                let family = base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family
                guard family == sa_family_t(AF_INET) else { return [] }

                var address = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil
                else { return [] }
                return [String(cString: buffer)]
            }
        }
    }
}

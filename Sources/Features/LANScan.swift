import Combine
import Darwin
import Foundation

// MARK: - Models

enum LANDeviceKind: String, Codable, CaseIterable, Sendable {
    case router
    case computer
    case laptop
    case desktop
    case appleDevice
    case printer
    case scanner
    case speaker
    case tv
    case mediaPlayer
    case smartHome

    /// Sort order for the device list: infrastructure first, then the things
    /// people look for by name.
    var rank: Int {
        switch self {
        case .router: return 0
        case .computer, .laptop, .desktop: return 1
        case .appleDevice: return 2
        case .printer, .scanner: return 3
        case .tv, .mediaPlayer: return 4
        case .speaker: return 5
        case .smartHome: return 6
        }
    }

    init?(serviceType: String, model: String?, txt: [String: String]) {
        let type = serviceType.lowercased()
        let model = (model ?? txt["model"] ?? txt["md"] ?? "").lowercased()
        if type.contains("_ipp") || type.contains("_printer") || model.contains("printer") {
            self = .printer
        } else if type.contains("_scanner") || model.contains("scanner") {
            self = .scanner
        } else if type.contains("_airplay") || type.contains("_raop") || model.contains("airport") {
            self = .appleDevice
        } else if type.contains("_googlecast") || model.contains("tv") {
            self = .tv
        } else if type.contains("_sonos") || model.contains("speaker") {
            self = .speaker
        } else if type.contains("_hap") || type.contains("_homekit") {
            self = .smartHome
        } else if type.contains("_companion-link") || model.contains("mac") {
            self = .computer
        } else {
            return nil
        }
    }
}

struct LANDevice: Identifiable, Codable, Hashable, Sendable {
    let address: String
    let mac: String
    let name: String
    let hostname: String?
    let vendor: String?
    let kind: LANDeviceKind?
    /// The Mac family the service or model string named, when it named one.
    let machineFamily: MachineIdentity.Family?
    /// A model identifier or advertised model string, when there is one.
    let model: String?
    /// Ports that accepted a short TCP connection during the scan.
    let openPorts: [Int]
    let services: [String]
    let interface: String
    let isSelf: Bool
    let isGateway: Bool

    var id: String { address }

    var usesPrivateAddress: Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 192 && parts[1] == 168)
    }
}

struct LANSnapshot: Codable, Sendable {
    var scannedAt: Date
    var interface: String
    var subnet: String
    var gateway: String?
    var selfAddresses: [String]
    var devices: [LANDevice]

    static let empty = LANSnapshot(
        scannedAt: .distantPast,
        interface: "",
        subnet: "",
        gateway: nil,
        selfAddresses: [],
        devices: []
    )

    var isEmpty: Bool { devices.isEmpty }
}

// MARK: - Scanner

enum LANScan {
    struct Interface {
        let name: String
        let address: String
        let netmask: String
    }

    struct Neighbour {
        let mac: String
        let interface: String
    }

    struct Route {
        var interface: String?
        var gateway: String?

        init(interface: String? = nil, gateway: String? = nil) {
            self.interface = interface
            self.gateway = gateway
        }
    }

    final class NameBox: @unchecked Sendable {
        let lock = NSLock()
        private var storage: [String: String] = [:]

        var names: [String: String] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        var stored: [String: String] {
            get { names }
            set {
                lock.lock()
                storage = newValue
                lock.unlock()
            }
        }

        func store(_ name: String, for address: String) {
            lock.lock()
            storage[address] = name
            lock.unlock()
        }
    }

    /// The common vendor prefixes, enough to put a maker beside a MAC without
    /// shipping a full IEEE registry.
    static let ouis: [String: String] = [
        "AC:DE:48": "Apple", "00:1B:63": "Apple", "3C:22:FB": "Apple",
        "F0:18:98": "Apple", "A4:83:E7": "Apple", "D0:81:7A": "Apple",
        "B8:27:EB": "Raspberry Pi", "DC:A6:32": "Raspberry Pi",
        "E4:5F:01": "Raspberry Pi", "24:0A:C4": "Espressif",
        "3C:61:05": "Espressif", "84:CC:A8": "Espressif",
        "00:1A:7D": "Samsung", "8C:77:12": "Samsung", "F8:04:2E": "Samsung",
        "00:1E:C2": "Apple", "00:25:00": "Apple", "28:CF:E9": "Apple",
        "00:17:88": "Philips Hue", "EC:B5:FA": "Philips Hue",
        "00:04:20": "Sonos", "78:28:CA": "Sonos", "B8:E9:37": "Sonos",
        "00:1D:BA": "Sony", "FC:0F:E6": "Sony", "00:13:A9": "Sony",
        "00:1F:3A": "LG", "C4:36:6C": "LG", "2C:54:91": "LG",
        "00:1B:11": "Netgear", "A0:40:A0": "Netgear", "C0:3F:0E": "Netgear",
        "00:1D:7E": "Cisco", "F8:0B:CB": "Cisco", "00:18:39": "Cisco",
        "24:5A:4C": "Ubiquiti", "78:8A:20": "Ubiquiti", "F0:9F:C2": "Ubiquiti",
        "50:C7:BF": "TP-Link", "A4:2B:B0": "TP-Link", "98:DA:C4": "TP-Link",
        "00:1E:8F": "Canon", "00:00:85": "Canon", "F4:81:39": "Canon",
        "00:26:AB": "Epson", "38:9D:92": "Epson", "A4:EE:57": "Epson",
        "00:1B:A9": "Brother", "00:80:77": "Brother", "30:05:5C": "Brother",
        "44:65:0D": "Amazon", "74:C2:46": "Amazon", "F0:27:2D": "Amazon",
        "F4:F5:E8": "Google", "3C:5A:B4": "Google", "54:60:09": "Google",
        "00:1A:11": "Google", "00:0D:93": "Apple", "00:03:93": "Apple"
    ]

    // MARK: Addresses

    static func addressValue(_ text: String) -> UInt32? {
        var address = in_addr()
        guard inet_pton(AF_INET, text, &address) == 1 else { return nil }
        return UInt32(bigEndian: address.s_addr)
    }

    static func dotted(_ value: UInt32) -> String {
        let octets = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
        return octets.map(String.init).joined(separator: ".")
    }

    static func mask(width: Int) -> UInt32 {
        guard width > 0 else { return 0 }
        guard width < 32 else { return .max }
        return ~UInt32(0) << UInt32(32 - width)
    }

    static func prefixLength(_ netmask: String) -> Int {
        guard let value = addressValue(netmask) else { return 24 }
        return value.nonzeroBitCount
    }

    static func subnetString(_ address: String, prefix: Int) -> String {
        guard let value = addressValue(address) else { return address }
        return dotted(value & mask(width: prefix))
    }

    static func hosts(in address: String, prefix: Int) -> [String] {
        guard let value = addressValue(address), prefix >= 16, prefix <= 30 else { return [] }
        let network = value & mask(width: prefix)
        let broadcast = network | ~mask(width: prefix)
        guard broadcast > network + 1 else { return [] }
        // A /16 would be 65k probes; a settings pane should not do that.
        let count = min(Int(broadcast - network - 1), 1022)
        return (1...count).map { dotted(network + UInt32($0)) }
    }

    // MARK: Interfaces and routes

    static func interfaces() -> [Interface] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        var result: [Interface] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  (entry.pointee.ifa_flags & UInt32(IFF_UP)) != 0,
                  (entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }

            let name = String(cString: entry.pointee.ifa_name)
            guard !name.hasPrefix("utun"), !name.hasPrefix("bridge") else { continue }
            let ip = numericHost(address)
            guard !ip.isEmpty, !ip.hasPrefix("169.254.") else { continue }
            let netmask = entry.pointee.ifa_netmask.map(numericHost) ?? "255.255.255.0"
            result.append(Interface(name: name, address: ip, netmask: netmask))
        }
        return result
    }

    static func chooseInterface(from all: [Interface], defaultInterface: String?) -> Interface? {
        if let defaultInterface,
           let match = all.first(where: { $0.name == defaultInterface }) {
            return match
        }
        if let wifi = all.first(where: { $0.name == "en0" }) { return wifi }
        return all.first
    }

    static func defaultRoute() -> Route {
        let output = shell("/sbin/route", ["-n", "get", "default"])
        var route = Route()
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("interface:") {
                route.interface = String(trimmed.dropFirst("interface:".count)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("gateway:") {
                route.gateway = String(trimmed.dropFirst("gateway:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return route
    }

    static func shell(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    static func numericHost(_ addr: UnsafeMutablePointer<sockaddr>) -> String {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(addr.pointee.sa_len)
        guard getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return ""
        }
        return String(cString: host)
    }

    // MARK: Neighbours and names

    static func neighbourTable() -> [String: Neighbour] {
        let fromKernel = neighbourTableViaSysctl()
        return fromKernel.isEmpty ? neighbourTableViaARP() : fromKernel
    }

    /// The route socket's link-layer table. `arp -an` is empty on some recent
    /// macOS builds even while the kernel still has every neighbour.
    static func neighbourTableViaSysctl() -> [String: Neighbour] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return [:]
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }

        var table: [String: Neighbour] = [:]
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<rt_msghdr>.size <= length {
                let header = base.advanced(by: offset).assumingMemoryBound(to: rt_msghdr.self)
                let messageLength = Int(header.pointee.rtm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }

                var address = ""
                var mac = ""
                var interface = ""
                var cursor = base.advanced(by: offset + MemoryLayout<rt_msghdr>.size)
                let end = base.advanced(by: offset + messageLength)

                for index in 0..<Int(RTAX_MAX) {
                    guard cursor < end else { break }
                    let sockaddrPointer = cursor.assumingMemoryBound(to: sockaddr.self)
                    let size = Int(sockaddrPointer.pointee.sa_len)
                    guard size > 0 else { break }

                    if index == Int(RTAX_DST), sockaddrPointer.pointee.sa_family == UInt8(AF_INET) {
                        let internet = cursor.assumingMemoryBound(to: sockaddr_in.self)
                        address = dotted(UInt32(bigEndian: internet.pointee.sin_addr.s_addr))
                    } else if index == Int(RTAX_GATEWAY), sockaddrPointer.pointee.sa_family == UInt8(AF_LINK) {
                        let link = cursor.assumingMemoryBound(to: sockaddr_dl.self)
                        let count = Int(link.pointee.sdl_alen)
                        if count == 6 {
                            // sdl_data is the last field, and the address follows
                            // the interface name inside it.
                            let data = cursor.advanced(by: 8 + Int(link.pointee.sdl_nlen))
                                .assumingMemoryBound(to: UInt8.self)
                            mac = (0..<6).map { String(format: "%02X", data[$0]) }.joined(separator: ":")
                        }
                    } else if index == Int(RTAX_IFP), sockaddrPointer.pointee.sa_family == UInt8(AF_LINK) {
                        let link = cursor.assumingMemoryBound(to: sockaddr_dl.self)
                        let count = Int(link.pointee.sdl_nlen)
                        if count > 0 {
                            let name = UnsafeRawBufferPointer(start: cursor.advanced(by: 8), count: count)
                            interface = String(decoding: name, as: UTF8.self)
                        }
                    }

                    cursor = cursor.advanced(by: max((size + 3) & ~3, 4))
                }

                if !address.isEmpty, !mac.isEmpty {
                    table[address] = Neighbour(mac: mac, interface: interface)
                }
                offset += messageLength
            }
        }
        return table
    }

    static func neighbourTableViaARP() -> [String: Neighbour] {
        var table: [String: Neighbour] = [:]
        for line in shell("/usr/sbin/arp", ["-an"]).split(separator: "\n") {
            guard let open = line.firstIndex(of: "("),
                  let close = line.firstIndex(of: ")") else { continue }
            let address = String(line[line.index(after: open)..<close])
            guard address.split(separator: ".").count == 4 else { continue }

            guard let at = line.range(of: " at ") else { continue }
            let rest = line[at.upperBound...]
            guard let mac = rest.split(separator: " ").first.map(String.init),
                  mac.filter({ $0 == ":" }).count == 5,
                  !mac.contains("incomplete") else { continue }

            var interface = ""
            if let on = line.range(of: " on ") {
                interface = line[on.upperBound...].split(separator: " ").first.map(String.init) ?? ""
            }
            table[address] = Neighbour(mac: mac.uppercased(), interface: interface)
        }
        return table
    }

    static func reverseName(_ address: String) -> String? {
        var storage = sockaddr_storage()
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, address, &addr.sin_addr) == 1 else { return nil }
        memcpy(&storage, &addr, MemoryLayout<sockaddr_in>.size)

        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size),
                            &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard result == 0 else { return nil }
        let name = String(cString: host)
        return name.isEmpty ? nil : name
    }

    static func reverseNames(_ addresses: [String], deadline: TimeInterval) -> [String: String] {
        let box = NameBox()
        let group = DispatchGroup()
        for address in addresses {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                if let name = reverseName(address) {
                    box.store(name, for: address)
                }
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + deadline)
        return box.names
    }

    static func vendor(mac: String) -> String? {
        let normalized = mac.uppercased().replacingOccurrences(of: "-", with: ":")
        let prefix = String(normalized.prefix(8))
        return ouis[prefix]
    }

    // MARK: ICMP ping

    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count { sum += UInt32(bytes[index]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return ~UInt16(sum & 0xFFFF)
    }

    static func echoRequest(sequence: UInt16) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 8)
        packet[0] = 8 // echo request
        packet[1] = 0
        let id = UInt16(truncatingIfNeeded: getpid())
        packet[4] = UInt8(id >> 8)
        packet[5] = UInt8(id & 0xFF)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)
        let sum = checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xFF)
        return packet
    }

    static func isEchoReply(_ bytes: [UInt8], count: Int) -> Bool {
        if count >= 8, bytes[0] == 0 { return true }
        // Some kernels hand back the IPv4 header first.
        if count >= 28, bytes[0] >> 4 == 4, bytes[20] == 0 { return true }
        return false
    }

    /// Unprivileged ICMP datagram sockets are what SimplePing uses, so this
    /// works without asking for root just to populate a settings pane.
    static func ping(_ hosts: [String], wait: TimeInterval = 1.0) -> Set<String> {
        guard !hosts.isEmpty else { return [] }
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard descriptor >= 0 else { return [] }
        defer { close(descriptor) }

        var sent: [String] = []
        for (index, host) in hosts.enumerated() {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { continue }
            let packet = echoRequest(sequence: UInt16(truncatingIfNeeded: index))
            let result = packet.withUnsafeBytes { raw in
                withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(descriptor, raw.baseAddress, packet.count, 0,
                               $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if result > 0 { sent.append(host) }
        }
        guard !sent.isEmpty else { return [] }

        var replies = Set<String>()
        let deadline = Date().addingTimeInterval(wait)
        var buffer = [UInt8](repeating: 0, count: 1500)

        while Date() < deadline {
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let milliseconds = max(Int32(deadline.timeIntervalSinceNow * 1000), 0)
            let ready = poll(&pollDescriptor, 1, milliseconds)
            guard ready > 0 else { break }

            var storage = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let count = buffer.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(descriptor, raw.baseAddress, raw.count, 0, $0, &length)
                    }
                }
            }
            guard count > 0, isEchoReply(buffer, count: count) else { continue }
            let host = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    numericHost(UnsafeMutablePointer(mutating: $0))
                }
            }
            if !host.isEmpty { replies.insert(host) }
        }
        return replies
    }

    // MARK: Snapshot

    static func run() -> LANSnapshot {
        let route = defaultRoute()
        let all = interfaces()
        guard let chosen = chooseInterface(from: all, defaultInterface: route.interface) else {
            return .empty
        }
        let prefix = prefixLength(chosen.netmask)
        let subnet = subnetString(chosen.address, prefix: prefix)
        let scanned = hosts(in: chosen.address, prefix: prefix)
        let alive = ping(scanned)
        let neighbours = neighbourTable()

        var bonjour: [String: BonjourService] = [:]
        for service in BonjourScan.run() {
            for address in service.addresses where bonjour[address] == nil {
                bonjour[address] = service
            }
        }
        let ssdp = SSDPScan.run()

        var candidates = alive
        candidates.formUnion(neighbours.keys)
        candidates.formUnion(bonjour.keys)
        candidates.formUnion(ssdp.keys)
        if let gateway = route.gateway { candidates.insert(gateway) }
        candidates.insert(chosen.address)

        let openPorts = TCPProbe.scan(hosts: Array(candidates))
        let names = reverseNames(Array(candidates), deadline: 1.2)
        let network = addressValue(subnet)
        let maskValue = mask(width: prefix)
        // A Mac with Wi-Fi and Ethernet on the same subnet has two addresses;
        // both are this Mac, not a second machine that happens to run the same
        // services.
        let selfAddresses = all.map(\.address)

        var devices: [LANDevice] = []
        for address in candidates {
            guard let value = addressValue(address) else { continue }
            if let network, prefix < 32, (value & maskValue) != network { continue }
            if selfAddresses.contains(address), address != chosen.address { continue }
            let neighbour = neighbours[address]
            let advertised = bonjour[address]
            let upnp = ssdp[address]
            let hostname = names[address] ?? advertised?.hostName
            let isGateway = route.gateway == address
            let isSelf = selfAddresses.contains(address)
            let ports = openPorts[address] ?? []
            var vendor = neighbour.flatMap { vendor(mac: $0.mac) }
            let machineFamily = advertised.flatMap {
                MachineIdentity.Family.named($0.searchText)
            } ?? (isSelf ? MachineIdentity.current.family : nil)
            if vendor == nil, machineFamily != nil { vendor = "Apple" }

            let services = Array(Set((advertised.map { [$0.type] } ?? []) + (upnp?.services ?? []))).sorted()
            let haystack = [advertised?.searchText, upnp?.searchText, hostname, vendor,
                            advertised?.model, TCPProbe.labels(for: ports).joined(separator: " ")]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            let kind: LANDeviceKind?
            if isGateway {
                kind = .router
            } else if let machineFamily {
                kind = machineFamily.isPortable ? .laptop : .desktop
            } else if ports.contains(62078)
                        || haystack.contains("iphone") || haystack.contains("ipad") {
                kind = .appleDevice
            } else if ports.contains(631) || ports.contains(9100)
                        || haystack.contains("printer") {
                kind = .printer
            } else if ports.contains(8009) || haystack.contains("tv")
                        || haystack.contains("television") || haystack.contains("mediarenderer") {
                kind = .tv
            } else if ports.contains(32400) || haystack.contains("plex") {
                kind = .mediaPlayer
            } else if haystack.contains("sonos") || haystack.contains("speaker") {
                kind = .speaker
            } else if haystack.contains("camera") || haystack.contains("doorbell") {
                kind = .smartHome
            } else if ports.contains(22) || ports.contains(445) || ports.contains(548) {
                kind = .computer
            } else {
                kind = nil
            }

            let fallbackName: String
            if isSelf {
                fallbackName = "This Mac"
            } else if isGateway {
                fallbackName = "Router"
            } else if let vendor {
                fallbackName = vendor
            } else {
                fallbackName = "Device " + (address.split(separator: ".").last.map(String.init) ?? "")
            }

            // Bonjour's friendly service name beats the machine-generated DNS
            // name, which is often just the address with dashes in it.
            let name = advertised?.name.isEmpty == false ? advertised!.name : (hostname ?? fallbackName)
            let model = advertised?.model ?? (isSelf ? MachineIdentity.current.hardwareModel : nil)

            devices.append(LANDevice(
                address: address,
                mac: neighbour?.mac ?? "—",
                name: name,
                hostname: hostname,
                vendor: vendor,
                kind: kind,
                machineFamily: machineFamily,
                model: model,
                openPorts: ports,
                services: services,
                interface: neighbour?.interface ?? chosen.name,
                isSelf: isSelf,
                isGateway: isGateway
            ))
        }

        devices.sort {
            if $0.isGateway != $1.isGateway { return $0.isGateway }
            if $0.isSelf != $1.isSelf { return $0.isSelf }
            return (addressValue($0.address) ?? 0) < (addressValue($1.address) ?? 0)
        }

        return LANSnapshot(
            scannedAt: Date(),
            interface: chosen.name,
            subnet: "\(subnet)/\(prefix)",
            gateway: route.gateway,
            selfAddresses: selfAddresses,
            devices: devices
        )
    }
}

// MARK: - Store

@MainActor
final class LANDevices: ObservableObject {
    static let shared = LANDevices()

    @Published var latest: LANSnapshot = .empty
    @Published var isScanning = false

    private var lastScan: Date?

    init() {}

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let snapshot = await Task.detached(priority: .utility) { LANScan.run() }.value
            latest = snapshot
            lastScan = Date()
            isScanning = false
        }
    }

    func refreshIfOlder(than interval: TimeInterval) {
        if let lastScan, Date().timeIntervalSince(lastScan) < interval { return }
        refresh()
    }
}

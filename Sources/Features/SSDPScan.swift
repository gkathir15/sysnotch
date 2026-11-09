import Darwin
import Foundation

/// One device that answered an SSDP M-SEARCH. The description URL is kept so a
/// later enrichment pass can read it without repeating discovery.
struct SSDPDevice: Sendable {
    let address: String
    let server: String?
    let location: String?
    let services: [String]

    var searchText: String {
        ([server, location] + services).compactMap { $0 }.joined(separator: " ")
    }
}

enum SSDPScan {
    private static let multicast = "239.255.255.250"
    private static let port: UInt16 = 1900

    static func run(timeout: TimeInterval = 1.2) -> [String: SSDPDevice] {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return [:] }
        defer { close(descriptor) }

        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR,
                   &reuse, socklen_t(MemoryLayout<Int32>.size))
        var ttl: UInt8 = 2
        setsockopt(descriptor, IPPROTO_IP, IP_MULTICAST_TTL,
                   &ttl, socklen_t(MemoryLayout<UInt8>.size))

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.bigEndian
        guard inet_pton(AF_INET, multicast, &destination.sin_addr) == 1 else { return [:] }

        let request = [
            "M-SEARCH * HTTP/1.1",
            "HOST: \(multicast):\(port)",
            "MAN: \"ssdp:discover\"",
            "MX: 1",
            "ST: ssdp:all",
            "", ""
        ].joined(separator: "\r\n")
        let bytes = Array(request.utf8)

        for _ in 0..<2 {
            bytes.withUnsafeBytes { raw in
                withUnsafePointer(to: &destination) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        _ = sendto(descriptor, raw.baseAddress, bytes.count, 0,
                                   $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var collected: [String: (server: String?, location: String?, services: Set<String>)] = [:]
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            var wait = timeval(tv_sec: 0, tv_usec: 150_000)
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO,
                       &wait, socklen_t(MemoryLayout<timeval>.size))

            var storage = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let count = buffer.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(descriptor, raw.baseAddress, raw.count, 0, $0, &length)
                    }
                }
            }
            guard count > 0 else { continue }

            let address = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    LANScan.numericHost(UnsafeMutablePointer(mutating: $0))
                }
            }
            guard !address.isEmpty else { continue }

            let response = String(decoding: buffer[0..<count], as: UTF8.self)
            let headers = parseHeaders(response)
            guard response.hasPrefix("HTTP/") else { continue }

            var entry = collected[address] ?? (nil, nil, [])
            if let server = headers["server"], !server.isEmpty { entry.server = server }
            if let location = headers["location"], !location.isEmpty { entry.location = location }
            for key in ["st", "nt"] {
                if let service = headers[key], !service.isEmpty {
                    entry.services.insert(service)
                }
            }
            collected[address] = entry
        }

        var result: [String: SSDPDevice] = [:]
        for (address, entry) in collected {
            result[address] = SSDPDevice(address: address,
                                         server: entry.server,
                                         location: entry.location,
                                         services: entry.services.sorted())
        }
        return result
    }

    private static func parseHeaders(_ response: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in response.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { headers[name] = value }
        }
        return headers
    }
}

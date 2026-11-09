import Darwin
import Foundation

/// A short, non-blocking TCP connect probe. Only hosts already discovered by
/// ping, ARP, Bonjour, or SSDP are probed, so a settings-pane scan does not
/// sweep every port on the whole subnet.
enum TCPProbe {
    static let ports = [22, 80, 443, 445, 548, 631, 8009, 9100, 32400, 62078]

    static func labels(for ports: [Int]) -> [String] {
        ports.compactMap { port in
            switch port {
            case 22:    return "SSH"
            case 80:    return "HTTP"
            case 443:   return "HTTPS"
            case 445:   return "SMB"
            case 548:   return "AFP"
            case 631:   return "IPP"
            case 8009:  return "Cast"
            case 9100:  return "Printer"
            case 32400: return "Plex"
            case 62078: return "Apple"
            default:    return nil
            }
        }
    }

    static func scan(hosts: [String], timeout: TimeInterval = 0.28) -> [String: [Int]] {
        guard !hosts.isEmpty else { return [:] }
        let lock = NSLock()
        var result: [String: [Int]] = [:]
        let group = DispatchGroup()

        for host in hosts {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                var open: [Int] = []
                let inner = DispatchGroup()
                let innerLock = NSLock()
                for port in ports {
                    inner.enter()
                    DispatchQueue.global(qos: .utility).async {
                        if connect(host: host, port: port, timeout: timeout) {
                            innerLock.lock()
                            open.append(port)
                            innerLock.unlock()
                        }
                        inner.leave()
                    }
                }
                inner.wait()
                if !open.isEmpty {
                    lock.lock()
                    result[host] = open.sorted()
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.wait()
        return result
    }

    private static func connect(host: String, port: Int, timeout: TimeInterval) -> Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return false }

        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            return false
        }

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&pollDescriptor, 1, Int32(timeout * 1000))
        guard ready > 0 else { return false }

        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else {
            return false
        }
        return error == 0
    }
}

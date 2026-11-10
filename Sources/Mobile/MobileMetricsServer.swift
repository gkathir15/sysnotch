import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

/// The addresses the Dock dashboard may connect to. Loopback is always there
/// for the Android emulator, which reaches its host as `10.0.2.2`; the LAN
/// addresses are limited to RFC 1918 so a Mac with a public address directly
/// on an interface never publishes its readings to the internet.
enum MobileMetricsNetwork {
    static func listenAddresses() -> [String] {
        var addresses = Set(LANScan.interfaces().map(\.address).filter(isPrivate))
        addresses.insert("127.0.0.1")
        return addresses.sorted()
    }

    static func isPrivate(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 192 && parts[1] == 168)
    }
}

enum MobileMetricsError: LocalizedError {
    case stopped

    var errorDescription: String? {
        switch self {
        case .stopped: return "The mobile dashboard server stopped."
        }
    }
}

/// Serves the Dock dashboard over a plain HTTP + Server-Sent Events socket.
///
/// The Android app asks for `GET /events` once and keeps the response open.
/// Every event is a complete snapshot, base64-encoded so a provider label or a
/// device name containing a newline cannot break the line-oriented stream.
/// This is intentionally unauthenticated, like the old loopback dashboard API,
/// so it is opt-in and binds only to loopback and private LAN addresses.
final class MobileMetricsServer: @unchecked Sendable {
    static let defaultPort = 8787

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let lock = NSLock()
    private var listeners: [Channel] = []
    private var clients: [ObjectIdentifier: Channel] = [:]
    /// The address each dashboard connected from, so Settings can say which
    /// phone is reading instead of only how many are. Kept beside `clients`
    /// because the channel is what frames are written to and the address is
    /// what the owner is told.
    private var clientAddresses: [ObjectIdentifier: String] = [:]
    private var latestJSON: Data?
    private var latestFrame: Data?
    private var keepAliveTask: RepeatedTask?
    private var stopped = false

    private(set) var boundPort = MobileMetricsServer.defaultPort

    /// Called on the server's event loop when a dashboard opens a stream. The
    /// owner uses it to ask for a fresh LAN scan; nothing about the HTTP
    /// request itself is allowed to wait for one.
    var onClientConnected: (() -> Void)?
    /// Called with the addresses of every dashboard reading right now,
    /// whenever one connects or leaves. Settings turns those into device names
    /// where the LAN scan knows one.
    var onClientsChanged: (([String]) -> Void)?

    var hasClients: Bool {
        lock.withLock { !clients.isEmpty }
    }

    var snapshotJSON: Data? {
        lock.withLock { latestJSON }
    }

    /// Bind loopback and every private IPv4 this Mac currently holds. Returns
    /// the addresses that were bound, so Settings can show exactly where the
    /// dashboard can reach this Mac.
    func start(port requestedPort: Int = MobileMetricsServer.defaultPort) async throws -> [String] {
        let hosts = requestedPort == 0 ? ["127.0.0.1"] : MobileMetricsNetwork.listenAddresses()
        var channels: [Channel] = []

        do {
            for host in hosts {
                let channel = try await ServerBootstrap(group: group)
                    .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .childChannelInitializer { [weak self] channel in
                        guard let self else {
                            return channel.eventLoop.makeFailedFuture(MobileMetricsError.stopped)
                        }
                        return channel.pipeline
                            .configureHTTPServerPipeline(withPipeliningAssistance: false,
                                                         withErrorHandling: true)
                            .flatMap {
                                channel.pipeline.addHandler(MobileMetricsHTTPHandler(server: self))
                            }
                    }
                    .bind(host: host, port: requestedPort)
                    .get()
                channels.append(channel)
            }
        } catch {
            for channel in channels { try? await channel.close().get() }
            try? await group.shutdownGracefully()
            throw error
        }

        lock.withLock {
            listeners = channels
            stopped = false
        }

        if let actual = channels.first?.localAddress?.port {
            boundPort = actual
        }

        keepAliveTask = group.next().scheduleRepeatedTask(
            initialDelay: .seconds(15),
            delay: .seconds(15)
        ) { [weak self] _ in
            self?.sendKeepAlive()
        }

        return hosts
    }

    /// Publish one complete JSON snapshot to every open dashboard and remember
    /// it for the next client that connects.
    func publish(json: Data) {
        let frame = Data("data: \(json.base64EncodedString())\n\n".utf8)
        let channels = lock.withLock { () -> [Channel] in
            latestJSON = json
            latestFrame = frame
            return Array(clients.values)
        }
        for channel in channels { deliver(frame, to: channel) }
    }

    func register(_ channel: Channel) {
        let id = ObjectIdentifier(channel)
        let (frame, addresses) = lock.withLock { () -> (Data?, [String]) in
            clients[id] = channel
            if let address = channel.remoteAddress?.ipAddress {
                clientAddresses[id] = address
            }
            return (latestFrame, clientAddressesLocked())
        }

        channel.closeFuture.whenComplete { [weak self] _ in
            self?.unregister(channel)
        }
        if let frame { deliver(frame, to: channel) }
        onClientConnected?()
        onClientsChanged?(addresses)
    }

    func unregister(_ channel: Channel) {
        let id = ObjectIdentifier(channel)
        let addresses = lock.withLock { () -> [String] in
            _ = clients.removeValue(forKey: id)
            _ = clientAddresses.removeValue(forKey: id)
            return clientAddressesLocked()
        }
        onClientsChanged?(addresses)
    }

    /// Unique client addresses, sorted, so two reconnects from one phone read
    /// as one device. The lock is already held by the caller.
    private func clientAddressesLocked() -> [String] {
        Array(Set(clientAddresses.values)).sorted()
    }

    private func deliver(_ data: Data, to channel: Channel) {
        channel.eventLoop.execute {
            guard channel.isActive else { return }
            var buffer = channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(buffer)))
                .whenFailure { _ in channel.close(promise: nil) }
        }
    }

    /// A chunked response with no `Content-Length` is still a body the client
    /// is reading. A comment every fifteen seconds keeps the Android socket's
    /// 45-second read timeout from turning an idle evening into a reconnect.
    private func sendKeepAlive() {
        let channels = lock.withLock { Array(clients.values) }
        let comment = Data(": keep-alive\n\n".utf8)
        for channel in channels { deliver(comment, to: channel) }
    }

    func stop() async {
        let state = lock.withLock { () -> (listeners: [Channel], clients: [Channel])? in
            guard !stopped else { return nil }
            stopped = true
            let listeners = self.listeners
            self.listeners = []
            let clients = Array(self.clients.values)
            self.clients = [:]
            self.clientAddresses = [:]
            return (listeners, clients)
        }
        guard let state else { return }

        keepAliveTask?.cancel()
        keepAliveTask = nil
        for channel in state.clients { try? await channel.close().get() }
        for channel in state.listeners { try? await channel.close().get() }
        try? await group.shutdownGracefully()
    }
}

private final class MobileMetricsHTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart

    private let server: MobileMetricsServer
    private var streaming = false
    private var responded = false

    init(server: MobileMetricsServer) {
        self.server = server
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let request):
            handle(request, context: context)
        case .body:
            break
        case .end:
            break
        }
    }

    private func handle(_ request: HTTPRequestHead, context: ChannelHandlerContext) {
        guard !responded, !streaming else { return }
        guard request.method == .GET else {
            respondError(status: .methodNotAllowed, message: "method-not-allowed", context: context)
            return
        }
        // Android's socket client sends no Origin. Browsers do, and a web page
        // on the LAN has no business reading this Mac's readings.
        guard request.headers["origin"].isEmpty,
              !request.headers["sec-fetch-site"].contains(where: {
                  $0.caseInsensitiveCompare("cross-site") == .orderedSame
              }) else {
            respondError(status: .forbidden, message: "local-client-only", context: context)
            return
        }

        let path = String(request.uri.split(separator: "?", maxSplits: 1).first ?? "")
        switch path {
        case "/events":
            openStream(context: context)
        case "/snapshot":
            guard let json = server.snapshotJSON else {
                respondError(status: .serviceUnavailable, message: "no-reading-yet", context: context)
                return
            }
            respondJSON(json, status: .ok, context: context)
        case "/health":
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            let body = Data("{\"ok\":true,\"app\":\"sysnotch\",\"api\":1,\"version\":\"\(version)\"}".utf8)
            respondJSON(body, status: .ok, context: context)
        default:
            respondError(status: .notFound, message: "not-found", context: context)
        }
    }

    private func openStream(context: ChannelHandlerContext) {
        streaming = true
        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: "text/event-stream")
        headers.add(name: "cache-control", value: "no-cache")
        headers.add(name: "connection", value: "keep-alive")
        headers.add(name: "transfer-encoding", value: "chunked")
        headers.add(name: "x-accel-buffering", value: "no")
        context.writeAndFlush(NIOAny(HTTPServerResponsePart.head(
            HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        ))).whenFailure { _ in context.close(promise: nil) }
        server.register(context.channel)
    }

    private func respondJSON(_ body: Data, status: HTTPResponseStatus,
                             context: ChannelHandlerContext) {
        responded = true
        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: "application/json; charset=utf-8")
        headers.add(name: "content-length", value: "\(body.count)")
        headers.add(name: "connection", value: "close")
        context.write(NIOAny(HTTPServerResponsePart.head(
            HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        )), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)))
            .whenComplete { _ in context.close(promise: nil) }
    }

    private func respondError(status: HTTPResponseStatus, message: String,
                              context: ChannelHandlerContext) {
        let body = Data("{\"error\":\"\(message)\"}".utf8)
        respondJSON(body, status: status, context: context)
    }

    func channelInactive(context: ChannelHandlerContext) {
        server.unregister(context.channel)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

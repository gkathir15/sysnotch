import Combine
import Foundation

/// Owns the opt-in dashboard server and keeps its last frame in step with the
/// same readings the notch draws. One hub for the app: Settings shows its
/// state, and the app delegate attaches the store once at launch.
@MainActor
final class MobileMetricsHub: ObservableObject {
    static let shared = MobileMetricsHub()

    @Published private(set) var isStarting = false
    @Published private(set) var listeners: [String] = []
    @Published private(set) var error: String?
    /// Where each dashboard reading right now connected from. Settings names
    /// these through the LAN scan, so an enabled switch that no phone has
    /// found is distinguishable from a connection that is working.
    @Published private(set) var connectedAddresses: [String] = []

    private var server: MobileMetricsServer?
    private weak var store: UsageStore?
    private var attached = false
    private var enabled = false
    private var generation = 0
    private var stopTask: Task<Void, Never>?
    private var liveTimer: Timer?
    private var networkCancellable: AnyCancellable?

    var port: Int { server?.boundPort ?? MobileMetricsServer.defaultPort }

    /// The addresses a phone can actually type. Loopback is left out because
    /// it is only useful to the Android emulator, which has its own 10.0.2.2
    /// mapping.
    var displayAddresses: [String] {
        listeners.filter { $0 != "127.0.0.1" }
    }

    var isListening: Bool { !listeners.isEmpty }

    private init() {}

    func attach(store: UsageStore) {
        guard !attached else { return }
        attached = true
        self.store = store
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard enabled, server == nil, !isStarting, store != nil else { return }
        isStarting = true
        error = nil
        generation += 1
        let generation = generation
        let previousStop = stopTask
        let server = MobileMetricsServer()
        server.onClientConnected = { [weak self] in
            Task { @MainActor [weak self] in
                self?.wakeNetwork()
            }
        }
        server.onClientsChanged = { [weak self] addresses in
            Task { @MainActor [weak self] in
                self?.connectedAddresses = addresses
                // The frame a new dashboard received on connect was the last
                // one published, which may be minutes old while no phone was
                // watching. Send a current one now rather than at the next
                // tick, so the first screen it draws is not stale.
                if !addresses.isEmpty { self?.publish() }
            }
        }
        self.server = server

        Task {
            // A quick off/on toggle must not race the old listeners' close:
            // binding 8787 again before the old sockets are gone fails with
            // "address already in use". The stop task is short and idempotent.
            await previousStop?.value
            do {
                let listeners = try await server.start()
                guard self.enabled, self.generation == generation else {
                    await server.stop()
                    return
                }
                self.listeners = listeners
                self.isStarting = false
                self.error = nil
                self.startLiveTimer()
                self.publish()
                // A dashboard's first frame should carry the network it is
                // looking at, not an empty block that fills in a scan later.
                // The scan is coalesced by LANDevices, so this is one pass even
                // if Settings already asked for one.
                self.networkCancellable = LANDevices.shared.$latest
                    .receive(on: RunLoop.main)
                    .sink { [weak self] _ in self?.publish() }
                LANDevices.shared.refreshIfOlder(than: 30)
            } catch {
                guard self.generation == generation else { return }
                self.isStarting = false
                self.listeners = []
                self.error = error.localizedDescription
                self.server = nil
                await server.stop()
            }
        }
    }

    private func stop() {
        enabled = false
        generation += 1
        isStarting = false
        listeners = []
        error = nil
        connectedAddresses = []
        liveTimer?.invalidate()
        liveTimer = nil
        networkCancellable?.cancel()
        networkCancellable = nil
        let server = self.server
        self.server = nil
        if let server {
            stopTask = Task { await server.stop() }
        }
    }

    /// Called at quit, when an async stop has nowhere to be awaited.
    func shutdown() {
        stop()
    }

    /// The dashboard's own label says `POLL: 1000MS`. System providers are
    /// local reads, so this is the same cadence the notch pays when a card is
    /// open; cloud providers are untouched. Nothing runs while no dashboard is
    /// connected, which keeps an enabled switch from doing work in the
    /// background.
    private func startLiveTimer() {
        liveTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
    }

    private func tick() {
        guard let server, server.hasClients else { return }
        store?.forceRefreshSystemProviders()
        // One frame per second, not one per provider update. Eight provider
        // snapshots landing together used to mean eight identical frames;
        // the dashboard redraws at 1 Hz and the e-ink panel does not benefit
        // from the extra traffic.
        publish()
    }

    private func publish() {
        guard let store, let server else { return }
        wakeNetwork()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        server.publish(json: MobileMetricsSnapshot.encode(
            snapshots: store.snapshots,
            network: LANDevices.shared.latest,
            version: version
        ))
    }

    /// A dashboard is watching, so the network block should not stay hours
    /// old. The scanner coalesces requests; this is safe to call on every
    /// provider update.
    private func wakeNetwork() {
        guard server?.hasClients == true else { return }
        LANDevices.shared.refreshIfOlder(than: 30)
    }
}

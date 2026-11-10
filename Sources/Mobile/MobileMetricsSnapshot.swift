import Foundation

/// The JSON the Android Dock dashboard reads from `/events` and `/snapshot`.
///
/// This is deliberately a separate wire shape from the app's display models:
/// the dashboard is an external client and its field names are part of its
/// contract. Keep the provider, metric and network blocks in sync with
/// `app/src/main/java/com/example/dock/data/Metrics.kt` in the Dock project.
///
/// `providers` is the notch's own model — one entry per ring — and carries the
/// same windows the tooltip draws. `metrics` is the dashboard's flat view of
/// the Mac's system health: one entry each for memory, CPU, GPU, disk,
/// thermals, network, energy and fans, with every row already labelled and
/// formatted. The dashboard can render a metric card without knowing which
/// notch cell supplied it, which is what lets it show memory, CPU and GPU as
/// their own readings rather than as one merged list.
enum MobileMetricsSnapshot {
    private struct Root: Encodable {
        let version: String
        let generatedAt: String
        let machine: Machine
        let providers: [Provider]
        let metrics: [Metric]
        let network: Network?
    }

    private struct Machine: Encodable {
        let name: String
        let chip: String
        let family: String
        let memory: String
        let cores: Int
        let portable: Bool
    }

    private struct Provider: Encodable {
        let id: String
        let name: String
        let kind: String
        let status: String
        let headline: String
        let ringFraction: Double?
        let windows: [Window]
        let block: Block?
    }

    private struct Window: Encodable {
        let id: String
        let group: String?
        let label: String
        let usedFraction: Double?
        let usedText: String?
        let detail: String?
        let remaining: Int?
        let used: Int?
    }

    private struct Block: Encodable {
        let reason: String
        let resetsAt: String?
    }

    /// One system metric as the dashboard shows it: a heading, the figure the
    /// ring means, and every individual reading under it.
    private struct Metric: Encodable {
        let id: String
        let name: String
        let headline: String
        let fraction: Double?
        let readings: [Reading]
    }

    private struct Reading: Encodable {
        let id: String
        let label: String
        let value: String
        let detail: String?
        let fraction: Double?
    }

    private struct Network: Encodable {
        let scannedAt: String
        let interface: String
        let subnet: String
        let gateway: String?
        let selfAddresses: [String]
        let devices: [Device]
    }

    private struct Device: Encodable {
        let address: String
        let mac: String
        let name: String
        let hostname: String?
        let vendor: String?
        let kind: String?
        let machineFamily: String?
        let model: String?
        let openPorts: [Int]
        let services: [String]
        let isSelf: Bool
        let isGateway: Bool
    }

    /// Encode one complete dashboard frame. Every publish is a full snapshot,
    /// so a client that missed a frame never has to merge partial state.
    static func encode(snapshots: [ProviderSnapshot],
                       network: LANSnapshot,
                       version: String,
                       generatedAt: Date = Date()) -> Data {
        let machine = MachineIdentity.current
        let root = Root(
            version: version,
            generatedAt: iso(generatedAt),
            machine: Machine(
                name: machine.displayName,
                chip: machine.chip,
                family: machine.family.rawValue,
                memory: machine.memoryText,
                cores: machine.coreCount,
                portable: machine.isPortable
            ),
            providers: snapshots.map(provider),
            metrics: snapshots.filter { $0.id.hasPrefix("system-") }.map(metric),
            network: network.scannedAt == .distantPast || network.interface.isEmpty
                ? nil
                : Network(
                    scannedAt: iso(network.scannedAt),
                    interface: network.interface,
                    subnet: network.subnet,
                    gateway: network.gateway,
                    selfAddresses: network.selfAddresses,
                    devices: network.devices.map(device)
                )
        )
        return (try? JSONEncoder().encode(root)) ?? Data("{}".utf8)
    }

    private static func provider(_ snapshot: ProviderSnapshot) -> Provider {
        Provider(
            id: snapshot.id,
            name: snapshot.displayName,
            kind: snapshot.kind == .localRuntime ? "localRuntime" : "usage",
            status: status(snapshot.status),
            headline: snapshot.headlineText,
            ringFraction: snapshot.ringFraction,
            windows: snapshot.windows.map { window in
                Window(
                    id: window.id,
                    group: window.group,
                    label: window.label,
                    usedFraction: window.usedFraction,
                    usedText: window.usedText,
                    detail: window.detail,
                    remaining: window.remaining,
                    used: window.used
                )
            },
            block: snapshot.block.map {
                Block(reason: $0.reason, resetsAt: $0.resetsAt.map(iso))
            }
        )
    }

    /// The provider's windows, flattened into rows a dashboard can draw
    /// without knowing how a `LimitWindow` is normally rendered. The value is
    /// the formatted reading the tooltip already shows; the detail adds the
    /// denominator when there is one.
    private static func metric(_ snapshot: ProviderSnapshot) -> Metric {
        Metric(
            id: snapshot.id,
            name: snapshot.displayName,
            headline: snapshot.headlineText,
            fraction: snapshot.ringFraction,
            readings: snapshot.windows.map { window in
                Reading(
                    id: window.id,
                    label: window.label,
                    value: window.usedText ?? window.detail ?? window.summary,
                    detail: window.detail == window.usedText ? nil : window.detail,
                    fraction: window.usedFraction
                )
            }
        )
    }

    private static func device(_ device: LANDevice) -> Device {
        Device(
            address: device.address,
            mac: device.mac,
            name: device.name,
            hostname: device.hostname,
            vendor: device.vendor,
            kind: device.kind?.rawValue,
            machineFamily: device.machineFamily?.rawValue,
            model: device.model,
            openPorts: device.openPorts,
            services: device.services,
            isSelf: device.isSelf,
            isGateway: device.isGateway
        )
    }

    private static func status(_ status: ProviderStatus) -> String {
        switch status {
        case .ok: return "ok"
        case .stale: return "stale"
        case .needsAuth, .signedOutByOwner: return "needsAuth"
        case .accessDenied: return "accessDenied"
        case .unsupported: return "unsupported"
        case .error: return "error"
        }
    }

    /// ISO-8601 UTC with a `Z`, no fractional seconds. The dashboard parses it
    /// as a timestamp, and a locale-dependent format would make that fail on
    /// exactly the machines this server is meant to serve.
    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

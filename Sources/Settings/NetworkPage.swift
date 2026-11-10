import SwiftUI

/// The settings pane for the Mac's current network and the devices beside it.
/// The scan is on demand rather than continuous: a settings pane should not
/// keep waking the Wi-Fi radio in the background.
struct NetworkPage: View {
    @ObservedObject private var lan = LANDevices.shared
    @ObservedObject private var mobile = MobileMetricsHub.shared
    @ObservedObject var preferences: Preferences
    private let machine = MachineIdentity.current

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.t("Model"), value: machine.displayName)
                LabeledContent(L10n.t("Chip"), value: machine.chip)
                LabeledContent(L10n.t("Cores"), value: "\(machine.coreCount)")
                LabeledContent(L10n.t("Memory"), value: machine.memoryText)
            } header: {
                Text(L10n.t("This Mac"))
            }

            Section {
                if lan.latest.interface.isEmpty {
                    HStack(spacing: 8) {
                        if lan.isScanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "wifi.slash")
                                .foregroundStyle(.secondary)
                        }
                        Text(lan.isScanning
                             ? L10n.t("Scanning this network…")
                             : L10n.t("No active network found."))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LabeledContent(L10n.t("Interface"), value: lan.latest.interface)
                    LabeledContent(L10n.t("Address"), value: addressText)
                    LabeledContent(L10n.t("Subnet"), value: lan.latest.subnet)
                    LabeledContent(L10n.t("Router"), value: lan.latest.gateway ?? "—")
                }

                HStack(spacing: 10) {
                    if lan.isScanning {
                        ProgressView().controlSize(.small)
                        Text(L10n.t("Scanning this network…"))
                            .foregroundStyle(.secondary)
                    } else if lan.latest.scannedAt != .distantPast {
                        Text(L10n.t("Last scanned") + " "
                             + lan.latest.scannedAt.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.t("Not scanned yet."))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button {
                        lan.refresh()
                    } label: {
                        Label(L10n.t("Scan"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(lan.isScanning)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Text(L10n.t("Network"))
            } footer: {
                Text(L10n.t("Names come from Bonjour, SSDP, and reverse DNS; open ports come from a short TCP probe. A Mac's family comes from its advertised model."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle(L10n.t("Allow the Dock app on this network"),
                       isOn: $preferences.mobileDashboardEnabled)
                Text(L10n.t("Dock shows the same system readings and network devices on your phone or tablet. The server is opt-in and only accepts connections on this Mac's local network."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if preferences.mobileDashboardEnabled {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(statusText)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Who is actually reading, not just how many: the LAN
                    // scan usually knows the phone's name, and the address is
                    // there when it does not.
                    ForEach(mobile.connectedAddresses, id: \.self) { address in
                        let client = connectedClient(for: address)
                        HStack(spacing: 7) {
                            Image(systemName: "iphone")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(client.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 8)
                            if let detail = client.address {
                                Text(detail)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error = mobile.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !mobile.displayAddresses.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(mobile.displayAddresses, id: \.self) { address in
                                HStack(spacing: 6) {
                                    Image(systemName: "iphone")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    Text("\(address):\(mobile.port)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } header: {
                Text(L10n.t("Mobile Dashboard"))
            } footer: {
                Text(L10n.t("Open Dock on your phone, enter one of these addresses and port \(mobile.port), and keep both devices on the same Wi-Fi. Nothing leaves your local network."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                NetworkTopologyView(devices: lan.latest.devices,
                                    gateway: lan.latest.gateway,
                                    isScanning: lan.isScanning)
                    .frame(height: 320)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            } header: {
                Text(L10n.t("Connection Topology"))
            }

            Section {
                if lan.latest.devices.isEmpty {
                    Text(lan.isScanning
                         ? L10n.t("Looking for devices…")
                         : L10n.t("No devices answered. Guest networks often isolate clients from each other."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(lan.latest.devices) { device in
                        deviceRow(device)
                    }
                }
            } header: {
                HStack(spacing: 8) {
                    Text(L10n.t("Network Devices"))
                    if !lan.latest.devices.isEmpty {
                        Text("\(lan.latest.devices.count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .onAppear {
            lan.refreshIfOlder(than: 30)
        }
    }

    /// The pane's one spelling of "where this Mac can be found": the first
    /// address is the one the Dock address rows will repeat, and the rest are
    /// kept because a Mac with several interfaces has several.
    private var addressText: String {
        lan.latest.selfAddresses.isEmpty
            ? "—"
            : lan.latest.selfAddresses.joined(separator: ", ")
    }

    private var statusColor: Color {
        if mobile.error != nil { return .orange }
        if mobile.isStarting { return .secondary }
        return mobile.isListening ? .green : .secondary
    }

    private var statusText: String {
        if mobile.isStarting { return L10n.t("Starting the dashboard server…") }
        if mobile.error != nil { return L10n.t("The dashboard server could not start.") }
        guard mobile.isListening else { return L10n.t("Waiting for a local network address…") }
        switch mobile.connectedAddresses.count {
        case 0:
            return mobile.displayAddresses.isEmpty
                ? L10n.t("Listening on this Mac only.")
                : L10n.t("Listening on this network.")
        case 1:
            return L10n.t("1 device connected")
        default:
            return L10n.t("\(mobile.connectedAddresses.count) devices connected")
        }
    }

    /// A connected dashboard's friendly name, from the same scan that names
    /// the network's other devices. The loopback emulator is this Mac; an
    /// address the scan has not seen yet is shown as itself.
    private func connectedClient(for address: String) -> (name: String, address: String?) {
        if address == "127.0.0.1" || address == "::1" {
            return (L10n.t("This Mac (Dock)"), nil)
        }
        guard let device = lan.latest.devices.first(where: { $0.address == address }),
              !device.name.isEmpty else {
            return (address, nil)
        }
        return (device.name, device.name == address ? nil : address)
    }

    private func deviceRow(_ device: LANDevice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(for: device.kind))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(device.isGateway ? Color.accentColor : .secondary)
                .frame(width: 22, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if device.isSelf {
                        badge(L10n.t("This Mac"))
                    } else if device.isGateway {
                        badge(L10n.t("Router"))
                    }
                    if let family = device.machineFamily {
                        badge(family.label)
                    }
                    Spacer(minLength: 0)
                }

                let portLabels = TCPProbe.labels(for: device.openPorts).joined(separator: " · ")
                let details = [device.hostname, device.vendor, device.model,
                               portLabels.isEmpty ? nil : portLabels,
                               device.services.isEmpty ? nil : device.services.joined(separator: " · ")]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty && $0 != device.name && $0 != device.machineFamily?.label }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)

            VStack(alignment: .trailing, spacing: 3) {
                Text(device.address)
                    .font(.system(size: 12, design: .monospaced))
                if device.mac != "—" {
                    Text(device.mac)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 128, alignment: .trailing)
            .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }

    private func symbol(for kind: LANDeviceKind?) -> String {
        switch kind {
        case .router: return "wifi.router.fill"
        case .computer: return "desktopcomputer"
        case .laptop: return "laptopcomputer"
        case .desktop: return "desktopcomputer"
        case .appleDevice: return "apple.logo"
        case .printer: return "printer.fill"
        case .scanner: return "scanner.fill"
        case .speaker: return "hifispeaker.fill"
        case .tv, .mediaPlayer: return "tv.fill"
        case .smartHome: return "house.fill"
        case nil: return "network"
        }
    }
}

/// A small hub-and-spoke map: the router at the center, this Mac first among
/// the spokes, then everything else Bonjour and the subnet scan found.
private struct NetworkTopologyView: View {
    let devices: [LANDevice]
    let gateway: String?
    let isScanning: Bool
    @Environment(\.codenotchAccentColor) private var accentColor

    /// Six nodes is what fits around the router before the labels start
    /// touching at the settings pane's narrowest width. Anything beyond that
    /// becomes a `+N more` node, which is honest about what is off the map and
    /// keeps every other node where it was.
    private static let maxNodes = 6
    private static let nodeWidth: CGFloat = 96
    private static let nodeHalfWidth: CGFloat = 48
    private static let nodeHeight: CGFloat = 74
    private static let nodeHalfHeight: CGFloat = 37

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let detail: String
        let symbol: String
        let isSelf: Bool
    }

    private var router: LANDevice? {
        devices.first { $0.isGateway }
    }

    private var entries: [Entry] {
        var result: [Entry] = []
        if let selfDevice = devices.first(where: \.isSelf) {
            result.append(entry(for: selfDevice))
        }
        let others = devices.filter { !$0.isGateway && !$0.isSelf }
            .sorted { left, right in
                let leftRank = left.kind?.rank ?? 99
                let rightRank = right.kind?.rank ?? 99
                return leftRank == rightRank
                    ? left.name.localizedStandardCompare(right.name) == .orderedAscending
                    : leftRank < rightRank
            }
        let capacity = max(0, Self.maxNodes - result.count)
        result.append(contentsOf: others.prefix(capacity).map(entry))
        if others.count > capacity {
            let hidden = others.count - capacity
            result.append(Entry(id: "more",
                                name: "+\(hidden) more",
                                detail: L10n.t("on this network"),
                                symbol: "ellipsis",
                                isSelf: false))
        }
        return result
    }

    private func entry(for device: LANDevice) -> Entry {
        let ports = TCPProbe.labels(for: device.openPorts).joined(separator: " · ")
        let detail = device.machineFamily?.label
            ?? (ports.isEmpty ? (device.isSelf ? L10n.t("This Mac") : device.address) : ports)
        return Entry(id: device.id,
                     name: device.name,
                     detail: detail,
                     symbol: symbol(for: device.kind),
                     isSelf: device.isSelf)
    }

    private func symbol(for kind: LANDeviceKind?) -> String {
        switch kind {
        case .router: return "wifi.router.fill"
        case .computer: return "desktopcomputer"
        case .laptop: return "laptopcomputer"
        case .desktop: return "desktopcomputer"
        case .appleDevice: return "apple.logo"
        case .printer: return "printer.fill"
        case .scanner: return "scanner.fill"
        case .speaker: return "hifispeaker.fill"
        case .tv, .mediaPlayer: return "tv.fill"
        case .smartHome: return "house.fill"
        case nil: return "network"
        }
    }

    private var routerName: String {
        router?.name ?? L10n.t("Router")
    }

    private var routerDetail: String {
        router?.machineFamily?.label ?? (gateway ?? L10n.t("not found"))
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            // Inset by half a node and a little air, so a spoke's label never
            // reaches the edge of the card and gets clipped in a narrow pane.
            let radiusX = max(0, min(size.width / 2 - Self.nodeHalfWidth - 8, 220))
            let radiusY = max(0, min(size.height / 2 - Self.nodeHalfHeight - 8, 104))
            let points = entryPoints(count: entries.count,
                                     center: center,
                                     radiusX: radiusX,
                                     radiusY: radiusY)

            ZStack {
                Canvas { context, _ in
                    var path = Path()
                    for point in points {
                        path.move(to: center)
                        path.addLine(to: point)
                    }
                    context.stroke(path,
                                   with: .color(.secondary.opacity(0.22)),
                                   style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                routerView
                    .position(center)

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    nodeView(entry)
                        .position(points[index])
                }
            }
            .frame(width: size.width, height: size.height)
            .overlay {
                if devices.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: isScanning ? "arrow.triangle.2.circlepath" : "network.slash")
                            .font(.system(size: 18, weight: .light))
                        Text(isScanning ? L10n.t("Scanning this network…") : L10n.t("Scan to draw this network."))
                            .font(.caption)
                    }
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.28))
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.035))
        }
    }

    private var routerView: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(Color.white.opacity(0.08))
                Circle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                Image(systemName: "wifi.router.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(width: 54, height: 54)

            Text(routerName)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .frame(width: 104)
            Text(routerDetail)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 104)
        }
        .frame(width: 108)
    }

    private func nodeView(_ entry: Entry) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(entry.isSelf
                          ? accentColor.opacity(0.16)
                          : Color.secondary.opacity(0.08))
                Circle()
                    .strokeBorder(entry.isSelf
                                  ? accentColor.opacity(0.75)
                                  : Color.secondary.opacity(0.18),
                                  lineWidth: 1)
                Image(systemName: entry.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(entry.isSelf ? accentColor : .secondary)
            }
            .frame(width: 40, height: 40)

            Text(entry.name)
                .font(.system(size: 9, weight: entry.isSelf ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 88)
            Text(entry.detail)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 88)
        }
        .frame(width: Self.nodeWidth)
    }

    private func entryPoints(count: Int,
                             center: CGPoint,
                             radiusX: CGFloat,
                             radiusY: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        if count == 1 {
            let y = max(Self.nodeHalfHeight + 6, center.y - radiusY)
            return [CGPoint(x: center.x, y: y)]
        }
        return (0..<count).map { index in
            let angle = -Double.pi / 2 + Double(index) * (2 * Double.pi / Double(count))
            return CGPoint(x: center.x + CGFloat(cos(angle)) * radiusX,
                           y: center.y + CGFloat(sin(angle)) * radiusY)
        }
    }
}

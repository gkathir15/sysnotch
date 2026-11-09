import SwiftUI

/// The settings pane for the Mac's current network and the devices beside it.
/// The scan is on demand rather than continuous: a settings pane should not
/// keep waking the Wi-Fi radio in the background.
struct NetworkPage: View {
    @ObservedObject private var lan = LANDevices.shared
    private let machine = MachineIdentity.current

    var body: some View {
        Form {
            Section {
                if lan.latest.interface.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(lan.isScanning ? L10n.t("Scanning this network…") : L10n.t("No active network found."))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent(L10n.t("Model"), value: machine.displayName)
                    LabeledContent(L10n.t("Chip"), value: machine.chip)
                    LabeledContent(L10n.t("Memory"), value: machine.memoryText)
                    LabeledContent(L10n.t("Interface"), value: lan.latest.interface)
                    LabeledContent(L10n.t("Address"), value: lan.latest.selfAddresses.joined(separator: ", "))
                    LabeledContent(L10n.t("Subnet"), value: lan.latest.subnet)
                    LabeledContent(L10n.t("Router"), value: lan.latest.gateway ?? "—")
                }
            } header: {
                Text(L10n.t("This Mac"))
            }

            Section {
                NetworkTopologyView(devices: lan.latest.devices,
                                    gateway: lan.latest.gateway,
                                    isScanning: lan.isScanning)
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 10, trailing: 10))
            } header: {
                Text(L10n.t("Connection Topology"))
            } footer: {
                Text(L10n.t("Router at the center. Names come from Bonjour, SSDP, and reverse DNS; open ports come from a short TCP probe. A Mac's family comes from its advertised model."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section {
                if lan.latest.devices.isEmpty {
                    Text(lan.isScanning
                         ? L10n.t("Looking for devices…")
                         : L10n.t("No devices answered. Guest networks often isolate clients from each other."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(lan.latest.devices) { device in
                        deviceRow(device)
                    }
                }
            } header: {
                HStack(spacing: 10) {
                    Text(L10n.t("Network Devices"))
                    if !lan.latest.devices.isEmpty {
                        Text("\(lan.latest.devices.count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        lan.refresh()
                    } label: {
                        if lan.isScanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(L10n.t("Scan"), systemImage: "arrow.clockwise")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .disabled(lan.isScanning)
                }
            } footer: {
                if lan.latest.scannedAt != .distantPast {
                    Text(L10n.t("Last scanned") + " " + lan.latest.scannedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .onAppear {
            lan.refreshIfOlder(than: 30)
        }
    }

    private func deviceRow(_ device: LANDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(for: device.kind))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(device.isGateway ? Color.accentColor : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if device.isSelf {
                        badge(L10n.t("This Mac"))
                    } else if device.isGateway {
                        badge(L10n.t("Router"))
                    }
                    if let family = device.machineFamily {
                        badge(family.label)
                    }
                }

                let portLabels = TCPProbe.labels(for: device.openPorts).joined(separator: " · ")
                let details = [device.hostname, device.vendor, device.model,
                               portLabels.isEmpty ? nil : portLabels]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty && $0 != device.name && $0 != device.machineFamily?.label }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(device.address)
                    .font(.system(size: 12, design: .monospaced))
                if device.mac != "—" {
                    Text(device.mac)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
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
        let capacity = max(0, 7 - result.count)
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
            let radiusX = max(60, min(size.width * 0.37, 230))
            let radiusY = max(45, min(size.height * 0.33, 98))
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
            Text(routerDetail)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
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
        .frame(width: 96)
    }

    private func entryPoints(count: Int,
                             center: CGPoint,
                             radiusX: CGFloat,
                             radiusY: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        if count == 1 {
            return [CGPoint(x: center.x, y: max(50, center.y - radiusY))]
        }
        return (0..<count).map { index in
            let angle = -Double.pi / 2 + Double(index) * (2 * Double.pi / Double(count))
            return CGPoint(x: center.x + CGFloat(cos(angle)) * radiusX,
                           y: center.y + CGFloat(sin(angle)) * radiusY)
        }
    }
}

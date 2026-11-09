import SwiftUI

/// The settings pane for the Mac's current network and the devices beside it.
/// The scan is on demand rather than continuous: a settings pane should not
/// keep waking the Wi-Fi radio in the background.
struct NetworkPage: View {
    @ObservedObject private var lan = LANDevices.shared

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
                    LabeledContent(L10n.t("Interface"), value: lan.latest.interface)
                    LabeledContent(L10n.t("Address"), value: lan.latest.selfAddresses.first ?? "—")
                    LabeledContent(L10n.t("Subnet"), value: lan.latest.subnet)
                    LabeledContent(L10n.t("Router"), value: lan.latest.gateway ?? "—")
                }
            } header: {
                Text(L10n.t("This Mac"))
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
                    if device.isSelf {
                        Text(L10n.t("This Mac"))
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    } else if device.isGateway {
                        Text(L10n.t("Router"))
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }

                let details = [device.hostname, device.vendor]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty && $0 != device.name }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private func symbol(for kind: LANDeviceKind?) -> String {
        switch kind {
        case .router: return "wifi.router.fill"
        case .computer: return "desktopcomputer"
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

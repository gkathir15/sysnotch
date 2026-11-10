import AppKit

/// The menu bar icon, present only while `AppPresence.menuBar` is chosen.
///
/// It exists to be a way *into* the app, so it opens settings and offers Quit —
/// with no Dock tile there is otherwise nothing to right-click, and an app you
/// cannot quit is a worse problem than one you cannot see.
///
/// It also carries the same readings as the notch tooltips, so `NotchVisibility`
/// hidden stays usable: with the notch off screen the menu is where the
/// percentages and stale ages live.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    /// Readable so a test can measure what the bar was actually given; only
    /// `show` and `hide` make or unmake it.
    private(set) var item: NSStatusItem?
    private let onOpenSettings: () -> Void
    /// Refetch one provider, leaving the others alone.
    var onRefreshProvider: ((String) -> Void)?
    /// Refetch every provider.
    var onRefreshAll: (() -> Void)?
    /// Somebody has just opened the menu, so the readings in it are about to be
    /// read. Separate from `onRefreshAll`, which is the **Refresh now** item and
    /// must always fetch: this one is allowed to decide it has fetched recently
    /// enough — see `UsageStore.refreshBecauseSomeoneIsLooking`.
    var onLook: (() -> Void)?

    /// The latest readings, mirrored from the store. The menu is rebuilt from
    /// these every time it opens, so ages are fresh.
    var snapshots: [ProviderSnapshot] = []
    /// How a time is worded, from Settings. The notch follows this, and the
    /// item's menu is the same sentence, so it follows it too.
    var resetTimeFormat: ResetTimeFormat = .automatic
    /// The notch's decorated cells, read when the menu opens. A local runtime's
    /// own snapshot only lists its models; what each one is doing, how fast it
    /// answered and what it cost today are put on the cells by the view model,
    /// and the menu says the same things the cells do.
    var cells: () -> [ProviderSnapshot] = { [] }
    var activity: (ProviderSnapshot) -> ActivitySummary? = { _ in nil }

    init(onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        super.init()
    }

    var isShowing: Bool { item != nil }

    func show() {
        guard item == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.icon()
        item.button?.toolTip = L10n.t("Sys Notch")

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        self.item = item
    }

    func hide() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }

    // MARK: - Menu

    /// Rebuilt on every open rather than on every fetch: a menu built at fetch
    /// time would freeze "20 hr ago" until the next reading lands.
    func menuWillOpen(_ menu: NSMenu) {
        // Asked here rather than anywhere else because opening the menu is the
        // one unambiguous "read these numbers" gesture the item has. The fetch
        // it may start lands a moment later, and the rows below are built from
        // whatever has landed by the time the menu is next opened.
        onLook?()
        rebuild(menu: menu, now: Date())
    }

    /// Exposed for tests: what the menu says without needing a status item.
    func rebuild(menu: NSMenu, now: Date) {
        menu.removeAllItems()
        if snapshots.isEmpty {
            let empty = NSMenuItem(title: L10n.t("Waiting for the first reading…"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let cells = cells()
            for snapshot in snapshots {
                menu.addItem(providerItem(for: snapshot, cells: cells, now: now))
            }
        }
        menu.addItem(.separator())
        menu.addItem(
            withTitle: L10n.t("Refresh all"), action: #selector(refreshAll), keyEquivalent: "r"
        ).target = self
        menu.addItem(
            withTitle: L10n.t("Activity…"), action: #selector(openActivity), keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: L10n.t("Settings…"), action: #selector(openSettings), keyEquivalent: ","
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: L10n.t("Quit Sys Notch"), action: #selector(quit), keyEquivalent: "q"
        ).target = self
    }

    /// The menu bar mark: its own drawing, not the app icon shrunk down.
    ///
    /// A template image, which is what lets macOS tint it — dark on a light
    /// menu bar, light on a dark one, and correct against a wallpaper-tinted
    /// bar without the app knowing any of that. The full-colour app icon can do
    /// none of it: it would fight every system item beside it and ignore the
    /// user's appearance entirely.
    ///
    /// Vector, so it is drawn at whatever the bar asks for rather than scaled
    /// from a fixed bitmap.
    static func icon() -> NSImage? {
        guard let image = NSImage(named: "MenuBarIcon") else { return nil }
        // Menu bar items are laid out on an 18pt square; taller and macOS
        // clips it, shorter and it floats.
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }


    @objc private func openSettings() { onOpenSettings() }
    @objc private func openActivity() { Costs.showActivity() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func refreshProvider(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onRefreshProvider?(id)
    }

    @objc private func refreshAll() { onRefreshAll?() }

    /// One metric in the menu: its heading stays on the menu, and its readings
    /// live in a submenu that starts closed. Nine system providers with every
    /// row expanded is a wall of text nobody reads; collapsed by default means
    /// the menu is an index you can drill into, not a report you have to scroll.
    /// A metric with no rows is the row itself, because there is nothing to
    /// disclose.
    private func providerItem(for snapshot: ProviderSnapshot, cells: [ProviderSnapshot],
                              now: Date) -> NSMenuItem {
        let header = headerItem(for: snapshot, now: now)
        let lines = Self.detailLines(for: snapshot, cells: cells, activity: activity,
                                     now: now, format: resetTimeFormat)
        guard !lines.isEmpty else { return header }

        let submenu = NSMenu(title: header.title)
        for line in lines {
            let row = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            row.isEnabled = false
            submenu.addItem(row)
        }
        submenu.addItem(.separator())
        let refresh = NSMenuItem(title: L10n.t("Refresh"),
                                 action: #selector(refreshProvider(_:)), keyEquivalent: "")
        refresh.target = self
        refresh.representedObject = snapshot.id
        submenu.addItem(refresh)

        header.submenu = submenu
        return header
    }

    /// The provider's own row: name, headline figure, and age when stale — the
    /// same three facts the tooltip header shows. Clicking re-reads it; when it
    /// has readings the row opens its collapsed submenu instead, and Refresh
    /// is the first item in there.
    private func headerItem(for snapshot: ProviderSnapshot, now: Date) -> NSMenuItem {
        var title = "\(snapshot.displayName) — \(Self.headline(for: snapshot))"
        if snapshot.kind == .usage, let since = snapshot.status.staleSince, since != .distantPast {
            title += " · \(ElapsedCopy.ago(since: since, now: now))"
        }
        let header = NSMenuItem(title: title, action: #selector(refreshProvider(_:)), keyEquivalent: "")
        header.target = self
        header.representedObject = snapshot.id
        return header
    }

    /// A runtime has no headline figure of its own; its models have. The row
    /// says how many there are, and the lines under it say the rest.
    static func headline(for snapshot: ProviderSnapshot) -> String {
        if snapshot.kind == .localRuntime {
            return snapshot.localRuntime?.summary ?? "—"
        }
        return snapshot.hasReading ? snapshot.headlineText : "—"
    }

    /// Everything the tooltip says under its header: the blocked line first,
    /// then one row per limit window, or the status message when there is
    /// nothing metered. For a local runtime, one line per loaded model, built
    /// from its decorated cell. Pure, so the wording can be tested without a
    /// menu.
    ///
    /// `format` is the user's **Reset time** choice, and it has to be passed in:
    /// this is static, so it cannot read the controller's own copy, and the
    /// default is not the shipped behaviour but merely a default.
    static func detailLines(for snapshot: ProviderSnapshot, cells: [ProviderSnapshot] = [],
                            activity: (ProviderSnapshot) -> ActivitySummary? = { _ in nil },
                            now: Date, format: ResetTimeFormat = .automatic) -> [String] {
        let now = now
        if snapshot.kind == .localRuntime {
            let models = cells.filter { $0.providerID == snapshot.id && $0.localModel != nil }
            guard models.isEmpty else { return models.map { modelLine(for: $0, activity: activity($0)) } }
            // The header already says "No models loaded"; only a failure to
            // reach the server is worth a line of its own.
            return snapshot.localRuntime == nil ? [snapshot.statusMessage].compactMap { $0 } : []
        }
        if let block = snapshot.block {
            var lines = [block.summary(now: now)]
            lines += snapshot.windows.map { windowLine(for: $0, now: now, format: format) }
            return lines
        }
        if let message = snapshot.statusMessage {
            return [message]
        }
        return snapshot.windows.map { windowLine(for: $0, now: now, format: format) }
    }

    /// One loaded model on one line: what its cell prints, what it is doing,
    /// how full its context was, and what it cost today — the tooltip's rows,
    /// in the order the eye wants them.
    static func modelLine(for cell: ProviderSnapshot, activity: ActivitySummary?) -> String {
        guard let model = cell.localModel else { return cell.headlineText }
        var parts = [cell.headlineText]
        if let activity, activity.state == .working {
            parts.append(activity.note ?? activity.sessions.first?.name ?? L10n.t("Thinking"))
        }
        if let fraction = cell.localContextFraction {
            parts.append(L10n.t("Context \(Percent.text(for: fraction))%"))
        }
        if let ledger = cell.localLedger {
            parts.append(L10n.t("Today \(ledger.tokensTodayText)"))
        }
        return "\(model.name): \(parts.joined(separator: " · "))"
    }

    /// One metered window on one line: label, percentage burned, and reset —
    /// the same three the tooltip spreads over three lines.
    static func windowLine(for window: LimitWindow, now: Date,
                           format: ResetTimeFormat = .automatic) -> String {
        var line = "\(window.label): \(window.summary)"
        if let resetsAt = window.resetsAt {
            line += " · \(ResetCopy.text(for: resetsAt, now: now, format: format))"
        }
        return line
    }
}

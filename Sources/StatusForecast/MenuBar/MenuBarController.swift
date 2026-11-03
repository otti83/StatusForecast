import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {

    private let appState: AppState
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var observers: Set<AnyCancellable> = []
    private var contextMenu: NSMenu?

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hosting = NSHostingController(rootView: PopoverRootView()
            .environmentObject(appState))
        // Critical: stop NSHostingController from pushing SwiftUI ideal-size
        // changes into the popover. Without this, each tab's natural height
        // bleeds into popover.contentSize and the layout drifts when the
        // location picker expands.
        hosting.sizingOptions = []
        hosting.preferredContentSize = NSSize(width: 460, height: 720)
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 460, height: 720)

        configureButton()
        attachObservers()
        updateAppearance()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeft
    }

    private func attachObservers() {
        appState.$snapshot
            .sink { [weak self] _ in Task { @MainActor in self?.updateAppearance() } }
            .store(in: &observers)
        appState.$loadState
            .sink { [weak self] _ in Task { @MainActor in self?.updateAppearance() } }
            .store(in: &observers)
        appState.$preferences
            .sink { [weak self] _ in Task { @MainActor in self?.updateAppearance() } }
            .store(in: &observers)
    }

    private func updateAppearance() {
        guard let button = statusItem.button else { return }
        let prefs = appState.preferences
        let (image, title) = MenuBarIconRenderer.render(
            mode: prefs.displayMode,
            snapshot: appState.snapshot,
            iconStyle: prefs.iconStyle,
            showDecimal: prefs.showDegreeDecimal
        )
        button.image = image
        if let title {
            button.attributedTitle = title
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
        // Tooltip shows full status.
        var tooltipLines: [String] = []
        if let loc = prefs.selectedLocation { tooltipLines.append(loc.displayName) }
        if let current = appState.snapshot?.current {
            if let t = current.temperatureC { tooltipLines.append(L10n.tf("tooltip.now", t)) }
            if let h = current.humidity { tooltipLines.append(L10n.tf("tooltip.humidity", Int(h))) }
            if let w = current.windSpeedMps {
                let dirLabel = current.windDirectionDeg.map { WindDirectionMap.label(forDegrees: $0) } ?? ""
                let speed = String(format: "%.1f m/s", w)
                tooltipLines.append(dirLabel.isEmpty ? speed : "\(dirLabel) \(speed)")
            }
        }
        if let issues = appState.snapshot?.issues, !issues.isEmpty {
            tooltipLines.append("⚠ " + issues.map(\.message).joined(separator: ", "))
        }
        button.toolTip = tooltipLines.isEmpty ? "StatusForecast" : tooltipLines.joined(separator: "\n")
    }

    // MARK: - actions

    @objc private func handleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { togglePopover(); return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.option) {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.t("menu.refresh_now"), action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        let locItem = NSMenuItem(title: L10n.t("menu.switch_location"), action: nil, keyEquivalent: "")
        let locSub = NSMenu()
        for loc in appState.preferences.locations {
            let item = NSMenuItem(title: loc.displayName,
                                  action: #selector(selectLocation(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = loc.id
            if loc.id == appState.preferences.selectedLocationID { item.state = .on }
            locSub.addItem(item)
        }
        locItem.submenu = locSub
        menu.addItem(locItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("menu.about"), action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.t("menu.settings"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("menu.quit"), action: #selector(quitApp), keyEquivalent: "q").target = self

        self.contextMenu = menu
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Reset to nil so left-click goes back to togglePopover via action.
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    @objc private func refreshNow() { appState.refresh(force: true) }

    @objc private func selectLocation(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        appState.selectLocation(id)
    }

    @objc private func openSettings() {
        if popover.isShown { popover.performClose(nil) }
        appState.openSettings()
    }

    @objc private func showAbout() {
        if popover.isShown { popover.performClose(nil) }
        NSApp.activate(ignoringOtherApps: true)
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let credits = NSMutableAttributedString(string:
            "Weather data:\n" +
            "• Yahoo! JAPAN Weather API\n" +
            "• 気象庁 (JMA) bosai data — 政府標準利用規約 v2.0\n" +
            "• Open-Meteo — CC-BY 4.0\n\n" +
            "Built with Swift, SwiftUI, Swift Charts.\n"
        )
        credits.addAttribute(.font, value: NSFont.systemFont(ofSize: 11),
                             range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.applicationName: "StatusForecast",
            NSApplication.AboutPanelOptionKey.applicationVersion: version,
            NSApplication.AboutPanelOptionKey(rawValue: "Version"): "\(version) (build \(build))",
            NSApplication.AboutPanelOptionKey.credits: credits
        ])
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

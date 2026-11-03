import SwiftUI

enum PopoverTab: String, CaseIterable, Identifiable {
    case today, weekly, environment, map
    var id: String { rawValue }
    var labelKey: String {
        switch self {
        case .today:       return "tab.today"
        case .weekly:      return "tab.weekly"
        case .environment: return "tab.environment"
        case .map:         return "tab.map"
        }
    }
}

struct PopoverRootView: View {
    @EnvironmentObject var state: AppState
    @State private var tab: PopoverTab = .today
    @State private var locationPickerExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if locationPickerExpanded {
                locationList
            }
            Divider()
            Picker("", selection: $tab) {
                ForEach(PopoverTab.allCases) { t in
                    T(LocalizedStringKey(t.labelKey)).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
            Divider()
            footer
        }
        // Hard-anchor the whole tree to a fixed rect, top-aligned. This stops
        // each tab's intrinsic content height from leaking into VStack's
        // ideal size and shifting where the header sits.
        .frame(width: 460, height: 720, alignment: .top)
        .background(Color(NSColor.windowBackgroundColor))
        .background {
            // Invisible keyboard-shortcut sinks for Cmd+1/2/3 tab switching.
            Group {
                Button("") { tab = .today  }.keyboardShortcut("1", modifiers: .command)
                Button("") { tab = .weekly }.keyboardShortcut("2", modifiers: .command)
                Button("") { tab = .environment }.keyboardShortcut("3", modifiers: .command)
                Button("") { tab = .map }.keyboardShortcut("4", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        .environment(\.locale, state.effectiveLocale)
        .id(state.preferences.languageOverride)
        .onAppear {
            tab = .today
        }
    }

    /// URL to open the public weather page for the selected location.
    private var externalDetailURL: URL? {
        guard let loc = state.preferences.selectedLocation else { return nil }
        let lat = String(format: "%.4f", loc.latitude)
        let lon = String(format: "%.4f", loc.longitude)
        return URL(string: "https://open-meteo.com/en/docs?latitude=\(lat)&longitude=\(lon)")
    }

    private var header: some View {
        HStack(spacing: 8) {
            // Inline expanding picker — replaces SwiftUI Menu which spawns
            // an NSMenu that disrupts NSPopover's outside-click detection.
            Button {
                locationPickerExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(state.preferences.selectedLocation?.displayName ?? L10n.t("header.no_location"))
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: locationPickerExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            statusBadge
            if let url = externalDetailURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.borderless)
                .helpL("header.open_in_browser")
            }
            Button(action: { state.refresh(force: true) }) {
                Image(systemName: state.loadState.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .rotationEffect(.degrees(state.loadState.isLoading ? 360 : 0))
                    .animation(state.loadState.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: state.loadState.isLoading)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r", modifiers: .command)
            .helpL("header.refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var locationList: some View {
        VStack(spacing: 0) {
            Divider()
            ForEach(state.preferences.locations) { loc in
                Button {
                    state.selectLocation(loc.id)
                    locationPickerExpanded = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: loc.id == state.preferences.selectedLocationID
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(loc.id == state.preferences.selectedLocationID
                                             ? Color.accentColor : Color.secondary.opacity(0.4))
                            .font(.caption)
                        Text(loc.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(loc.id == state.preferences.selectedLocationID
                            ? Color.accentColor.opacity(0.08) : Color.clear)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch state.loadState {
        case .ready:
            EmptyView()
        case .idle, .loading:
            ProgressView().controlSize(.small)
        case .stale(let m):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .help(m)
        case .error(let m):
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .help(m)
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch tab {
            case .today:       NowView()
            case .weekly:      WeeklyView()
            case .environment: EnvironmentView()
            case .map:         MapView()
            }
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            if let last = state.snapshot?.fetchedAt {
                Text(L10n.tf("footer.last_updated", last.formatted(timeStyle)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var timeStyle: Date.FormatStyle {
        var s = Date.FormatStyle()
            .hour(.defaultDigits(amPM: .omitted))
            .minute(.twoDigits)
            .locale(state.effectiveLocale)
        s.timeZone = state.preferences.selectedLocation?.timeZone ?? .current
        return s
    }
}

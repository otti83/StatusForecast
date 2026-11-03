import AppKit
import SwiftUI

/// Generates the NSImage / NSAttributedString used by the menu bar status item
/// for each of the three display modes.
enum MenuBarIconRenderer {

    /// Returns (image, attributedTitle) — either may be nil depending on mode.
    static func render(
        mode: MenuBarDisplayMode,
        snapshot: WeatherSnapshot?,
        iconStyle: IconStyle,
        showDecimal: Bool
    ) -> (image: NSImage?, title: NSAttributedString?) {
        switch mode {
        case .realtime:
            return renderRealtime(snapshot: snapshot, iconStyle: iconStyle, showDecimal: showDecimal)
        case .daily:
            return renderDaily(snapshot: snapshot, iconStyle: iconStyle)
        case .weekly:
            return renderWeekly(snapshot: snapshot, iconStyle: iconStyle)
        }
    }

    // MARK: - realtime

    private static func renderRealtime(snapshot: WeatherSnapshot?, iconStyle: IconStyle, showDecimal: Bool) -> (NSImage?, NSAttributedString?) {
        let category = snapshot?.today.map { WeatherCategoryMap.category(for: $0.code) } ?? .unknown
        let symbol = symbolImage(for: category, iconStyle: iconStyle, size: 16)

        var titleText: String = ""
        if let temp = snapshot?.current?.temperatureC ?? snapshot?.today?.tempMaxC {
            titleText = showDecimal ? String(format: "%.1f°", temp) : "\(Int(temp.rounded()))°"
        } else {
            titleText = "—"
        }
        if let rain = snapshot?.current?.precip1hMm, rain >= 0.1 {
            titleText += " 💧"
        }

        return (symbol, attributedTitle(titleText))
    }

    // MARK: - daily

    private static func renderDaily(snapshot: WeatherSnapshot?, iconStyle: IconStyle) -> (NSImage?, NSAttributedString?) {
        let category = snapshot?.today.map { WeatherCategoryMap.category(for: $0.code) } ?? .unknown
        let symbol = symbolImage(for: category, iconStyle: iconStyle, size: 16)

        let min = snapshot?.today?.tempMinC
        let max = snapshot?.today?.tempMaxC ?? snapshot?.current?.temperatureC
        let title: String
        switch (min, max) {
        case let (m?, x?): title = "\(Int(m.rounded()))°/\(Int(x.rounded()))°"
        case (nil, let x?): title = "\(Int(x.rounded()))°"
        case (let m?, nil): title = "\(Int(m.rounded()))°"
        default:            title = "—"
        }
        return (symbol, attributedTitle(title))
    }

    // MARK: - weekly (composite of 7 mini icons)

    private static func renderWeekly(snapshot: WeatherSnapshot?, iconStyle: IconStyle) -> (NSImage?, NSAttributedString?) {
        let count = 7
        let iconSize: CGFloat = 14
        let spacing: CGFloat = 2
        let totalWidth = CGFloat(count) * iconSize + CGFloat(count - 1) * spacing
        let totalHeight = iconSize

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { rect in
            let weekly = (snapshot?.weekly ?? []).prefix(count)
            for i in 0..<count {
                let x = CGFloat(i) * (iconSize + spacing)
                let category: WeatherCategory
                if i < weekly.count {
                    category = WeatherCategoryMap.category(for: weekly[weekly.index(weekly.startIndex, offsetBy: i)].code)
                } else {
                    category = .unknown
                }
                let icon = symbolImage(for: category, iconStyle: iconStyle, size: iconSize)
                icon.draw(in: NSRect(x: x, y: 0, width: iconSize, height: iconSize),
                          from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            return true
        }
        image.isTemplate = (iconStyle == .monochrome)
        return (image, nil)
    }

    // MARK: - helpers

    private static func symbolImage(for category: WeatherCategory, iconStyle: IconStyle, size: CGFloat) -> NSImage {
        let config: NSImage.SymbolConfiguration
        if iconStyle == .color {
            config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
                .applying(.preferringMulticolor())
        } else {
            config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        }
        let image = NSImage(systemSymbolName: category.symbolName, accessibilityDescription: category.localizedLabel)?
            .withSymbolConfiguration(config) ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)!
        image.isTemplate = (iconStyle == .monochrome)
        return image
    }

    private static func attributedTitle(_ text: String) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        return NSAttributedString(string: " " + text, attributes: attrs)
    }
}

import SwiftUI

struct WeatherSymbol: View {
    let code: WeatherCodeRef
    var size: CGFloat = 28
    var useColor: Bool = true

    var body: some View {
        let category = WeatherCategoryMap.category(for: code)
        let palette = category.paletteColors
        Image(systemName: category.symbolName)
            .symbolRenderingMode(useColor ? .palette : .monochrome)
            .foregroundStyle(palette.primary, palette.secondary)
            .font(.system(size: size))
            .accessibilityLabel(category.localizedLabel)
    }
}

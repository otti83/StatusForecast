import SwiftUI
import MapKit

/// "Nearby" tab. A small MapKit view with a translucent temperature heatmap
/// (square grid cells, each filled by interpolated color) plus subtle wind
/// arrows for cells with appreciable wind.
struct MapView: View {
    @EnvironmentObject var state: AppState
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// Half-side length of one heatmap cell (degrees). Should match the
    /// spacing used in OpenMeteoGridClient (0.12) so cells tile cleanly.
    private let cellHalfDeg: Double = 0.06

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            map
            legend
        }
    }

    private var location: Location? { state.snapshot?.location }
    private var grid: [GridPoint] { state.snapshot?.grid ?? [] }

    @ViewBuilder
    private var header: some View {
        if let loc = location {
            Text(L10n.tf("map.subtitle", loc.displayName))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var map: some View {
        if let loc = location {
            let center = centerTemp ?? 0
            Map(position: $cameraPosition) {
                // Translucent anomaly heatmap — one square per grid cell,
                // colored by ΔT relative to the center cell. With most of
                // the area sitting within a degree or two of the center
                // temperature, an absolute scale just paints everything
                // the same color; an anomaly scale surfaces the structure.
                ForEach(grid) { gp in
                    let coords = cellCorners(lat: gp.latitude, lon: gp.longitude)
                    MapPolygon(coordinates: coords)
                        .foregroundStyle(anomalyColor(gp.temperatureC, center: center))
                        .stroke(Color.clear, lineWidth: 0)
                }

                // Center pin.
                Annotation(loc.displayName,
                           coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)) {
                    ZStack {
                        Circle().fill(Color.accentColor).frame(width: 10, height: 10)
                        Circle().stroke(Color.white, lineWidth: 1.5).frame(width: 10, height: 10)
                    }
                }
                .annotationTitles(.hidden)

                // Per-cell label: temperature number + (optional) wind arrow.
                ForEach(grid) { gp in
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: gp.latitude, longitude: gp.longitude)) {
                        VStack(spacing: 1) {
                            Text(gp.temperatureC.map { TempFormat.intLabel($0, in: state.preferences.unitSystem) } ?? "—")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.75), radius: 1, x: 0, y: 0.5)
                            if let deg = gp.windDirectionDeg,
                               let speed = gp.windSpeedMps, speed >= 1.5 {
                                Image(systemName: "location.north.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.7), radius: 1)
                                    .rotationEffect(.degrees(deg + 180))
                                    .opacity(min(0.95, 0.45 + speed / 12.0))
                            }
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
            )
            .onAppear { recenter(on: loc) }
            .onChange(of: state.preferences.selectedLocationID) { _, _ in
                if let l = state.snapshot?.location { recenter(on: l) }
            }
        } else {
            HStack {
                ProgressView().controlSize(.small)
                T("loading.map").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 360)
        }
    }

    private func recenter(on loc: Location) {
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.9, longitudeDelta: 0.9)
        ))
    }

    private func cellCorners(lat: Double, lon: Double) -> [CLLocationCoordinate2D] {
        [
            CLLocationCoordinate2D(latitude: lat - cellHalfDeg, longitude: lon - cellHalfDeg),
            CLLocationCoordinate2D(latitude: lat - cellHalfDeg, longitude: lon + cellHalfDeg),
            CLLocationCoordinate2D(latitude: lat + cellHalfDeg, longitude: lon + cellHalfDeg),
            CLLocationCoordinate2D(latitude: lat + cellHalfDeg, longitude: lon - cellHalfDeg)
        ]
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                T("map.legend.temp").font(.caption2).foregroundStyle(.secondary)
                ForEach(legendBuckets, id: \.0) { (offset, label, color) in
                    HStack(spacing: 2) {
                        Rectangle().fill(color).frame(width: 14, height: 8)
                        Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            HStack(spacing: 4) {
                T("map.legend.wind").font(.caption2).foregroundStyle(.secondary)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
    }

    /// Reference temperature for the heatmap — grid cell nearest the selected
    /// location, or the mean if that's missing.
    private var centerTemp: Double? {
        guard let loc = location, !grid.isEmpty else { return nil }
        let nearest = grid.min { lhs, rhs in
            let dl = pow(lhs.latitude - loc.latitude, 2) + pow(lhs.longitude - loc.longitude, 2)
            let dr = pow(rhs.latitude - loc.latitude, 2) + pow(rhs.longitude - loc.longitude, 2)
            return dl < dr
        }
        if let t = nearest?.temperatureC { return t }
        let vals = grid.compactMap(\.temperatureC)
        return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
    }

    /// Legend entries — absolute temperatures derived from a rounded
    /// center + integer offsets, so the swatches always step by exactly 1°
    /// without printf banker's-rounding collisions.
    private var legendBuckets: [(Double, String, Color)] {
        let unit = state.preferences.unitSystem
        let centerDisplay = TempFormat.value(centerTemp ?? 0, in: unit)
        let centerInt = Int(centerDisplay.rounded(.toNearestOrAwayFromZero))
        // 1°C ≈ 1.8°F, so step by 2 in Fahrenheit to keep labels meaningfully apart.
        let stepInt = unit == .imperial ? 2 : 1
        func lab(_ k: Int) -> String { "\(centerInt + k * stepInt)°" }
        return [
            (-2.0, lab(-2), Color.blue.opacity(0.55)),
            (-1.0, lab(-1), Color.blue.opacity(0.30)),
            ( 0.0, lab( 0), Color.green.opacity(0.30)),
            ( 1.0, lab( 1), Color.red.opacity(0.30)),
            ( 2.0, lab( 2), Color.red.opacity(0.55))
        ]
    }

    /// Anomaly coloring: ΔT in °C relative to the center, clamped to ±2.5°C.
    /// Cool side → blue, warm side → red, near-center → green.
    private func anomalyColor(_ value: Double?, center: Double) -> Color {
        guard let v = value else { return Color.green.opacity(0.15) }
        let delta = v - center
        let clamped = max(-2.5, min(2.5, delta))
        let mag = abs(clamped) / 2.5
        let alpha = 0.15 + mag * 0.40           // 0.15...0.55
        if clamped < -0.3 {
            return Color.blue.opacity(alpha)
        } else if clamped > 0.3 {
            return Color.red.opacity(alpha)
        } else {
            return Color.green.opacity(0.30)
        }
    }
}

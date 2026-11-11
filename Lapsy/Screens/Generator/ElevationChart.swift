import SwiftUI
import Charts

/// Elevation along the route. Dragging a finger across it moves `scrub`,
/// which the map uses to show where on the route that point is.
struct ElevationChart: View {
    let points: [ProfilePoint]
    @Binding var scrub: Int?

    var body: some View {
        let lows = points.map(\.elevation)
        let minE = (lows.min() ?? 0)
        let maxE = (lows.max() ?? 0)
        let pad = max(5, (maxE - minE) * 0.15)
        // Empty room above the line so the details label never covers the profile.
        let headroom = max(maxE - minE, 12) * 0.6

        Chart {
            ForEach(points) { p in
                AreaMark(
                    x: .value("km", p.km),
                    yStart: .value("base", minE - pad),
                    yEnd: .value("m", p.elevation)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Palette.primary.opacity(0.35), Palette.primary.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                LineMark(x: .value("km", p.km), y: .value("m", p.elevation))
                    .foregroundStyle(Palette.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let i = scrub, points.indices.contains(i) {
                RuleMark(x: .value("km", points[i].km))
                    .foregroundStyle(Palette.textPrimary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(
                        position: .overlay, alignment: .top, spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        tip(points[i])
                    }
                PointMark(x: .value("km", points[i].km), y: .value("m", points[i].elevation))
                    .foregroundStyle(Palette.tertiary)
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: (minE - pad)...(maxE + pad + headroom))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel()
                    .font(Typeface.label(9))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let frame = proxy.plotFrame else { return }
                                let x = value.location.x - geo[frame].origin.x
                                guard let km: Double = proxy.value(atX: x) else { return }
                                scrub = nearestIndex(to: km)
                            }
                            .onEnded { _ in scrub = nil }
                    )
            }
        }
    }

    /// Details for the point under the finger.
    private func tip(_ p: ProfilePoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.2f KM  ·  %.0f M", p.km, p.elevation))
                .foregroundStyle(Palette.textPrimary)
            Text("\(p.gradeText)  ·  \(p.surfaceText)".uppercased())
                .foregroundStyle(Palette.primary)
        }
        .font(Typeface.label(9))
        .tracking(0.5)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
            .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
    }

    private func nearestIndex(to km: Double) -> Int? {
        points.indices.min { abs(points[$0].km - km) < abs(points[$1].km - km) }
    }
}

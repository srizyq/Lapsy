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
                PointMark(x: .value("km", points[i].km), y: .value("m", points[i].elevation))
                    .foregroundStyle(Palette.tertiary)
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: (minE - pad)...(maxE + pad))
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

    private func nearestIndex(to km: Double) -> Int? {
        points.indices.min { abs(points[$0].km - km) < abs(points[$1].km - km) }
    }
}

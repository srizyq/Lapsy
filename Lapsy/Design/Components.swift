import SwiftUI
import CoreLocation

/// A route drawn as a plain line, scaled to fit. Used for thumbnails.
struct RouteShape: View {
    let coordinates: [CLLocationCoordinate2D]
    var color: Color = Palette.primary
    var lineWidth: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            guard coordinates.count > 1 else { return }
            let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
            let minLat = lats.min()!, maxLat = lats.max()!
            let minLon = lons.min()!, maxLon = lons.max()!
            // Longitude degrees are narrower away from the equator.
            let lonScale = cos((minLat + maxLat) / 2 * .pi / 180)
            let w = max((maxLon - minLon) * lonScale, 1e-9)
            let h = max(maxLat - minLat, 1e-9)
            let inset: CGFloat = 6
            let scale = min((size.width - inset * 2) / w, (size.height - inset * 2) / h)
            let offX = (size.width - w * scale) / 2
            let offY = (size.height - h * scale) / 2
            var path = Path()
            for (i, c) in coordinates.enumerated() {
                let p = CGPoint(
                    x: offX + (c.longitude - minLon) * lonScale * scale,
                    y: offY + (maxLat - c.latitude) * scale
                )
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Small rounded-corner tag.
struct Tag: View {
    let text: String
    var icon: String?
    var highlighted = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .medium)) }
            Text(text.uppercased())
                .font(Typeface.label(9))
                .tracking(0.6)
        }
        .foregroundStyle(highlighted ? Palette.onPrimary : Palette.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(highlighted ? Palette.primary : Palette.well)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
            .strokeBorder(highlighted ? .clear : Palette.hairline, lineWidth: Metrics.hairline))
    }
}

/// A selectable pill in a row of filters.
struct FilterChip: View {
    let title: String
    let selected: Bool
    var icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)) }
                Text(title.uppercased())
                    .font(Typeface.label(10, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundStyle(selected ? Palette.onPrimary : Palette.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? Palette.primary : Palette.well)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(selected ? .clear : Palette.hairline, lineWidth: Metrics.hairline))
        }
        .buttonStyle(.plain)
    }
}

/// Drag the handle all the way across to confirm.
struct SlideToConfirm: View {
    let title: String
    let action: () -> Void

    @State private var drag: CGFloat = 0
    private let handle: CGFloat = 48

    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - handle - 8)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Metrics.corner).fill(Palette.well)
                RoundedRectangle(cornerRadius: Metrics.corner)
                    .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
                Text(title.uppercased())
                    .font(Typeface.label(11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .opacity(1 - Double(drag / travel))
                Image(systemName: "pause.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.onPrimary)
                    .frame(width: handle, height: handle)
                    .background(Palette.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                    .offset(x: 4 + drag)
                    .gesture(
                        DragGesture()
                            .onChanged { drag = min(travel, max(0, $0.translation.width)) }
                            .onEnded { _ in
                                if drag > travel * 0.85 { action() }
                                withAnimation(.spring(duration: 0.25)) { drag = 0 }
                            }
                    )
            }
        }
        .frame(height: 56)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

/// Thin horizontal progress bar.
struct ProgressLine: View {
    let fraction: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.well)
                Rectangle().fill(Palette.primary)
                    .frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

import SwiftUI
import MapKit

struct RunDetailScreen: View {
    let run: SavedRun

    @Environment(\.dismiss) private var dismiss
    @Environment(RunStore.self) private var store
    @State private var confirmDelete = false

    private var current: SavedRun { store.runs.first { $0.id == run.id } ?? run }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        MonoLabel(Fmt.when(run.startedAt), color: Palette.primary)
                        Text(run.activity.name)
                            .font(Typeface.headline(26))
                            .foregroundStyle(Palette.textPrimary)
                        if !run.startName.isEmpty {
                            Text("From \(run.startName)")
                                .font(Typeface.body(13))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(Typeface.label(11))
                        .foregroundStyle(Palette.textSecondary)
                }

                map

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        stat("Distance", Fmt.km(run.distanceM), "km")
                        stat("Time", Fmt.clock(run.durationS), "")
                    }
                    HStack(spacing: 8) {
                        if run.activity.group == .wheels {
                            stat("Avg speed", run.averageSpeedKmh.map { String(format: "%.1f", $0) } ?? "--", "km/h")
                        } else {
                            stat("Avg pace", Fmt.pace(run.averagePaceSecPerKm), "/km")
                        }
                        stat("Energy", String(format: "%.0f", run.energyKcal), "kcal")
                    }
                    if let hr = run.avgHeartRate {
                        HStack(spacing: 8) {
                            stat("Avg heart", "\(hr)", "bpm")
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }

                if run.plannedPolyline != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        MonoLabel("How was this route?")
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { star in
                                Button { store.setRating(star, for: run.id) } label: {
                                    Image(systemName: star <= (current.rating ?? 0) ? "star.fill" : "star")
                                        .font(.system(size: 24))
                                        .foregroundStyle(star <= (current.rating ?? 0) ? Palette.primary : Palette.textMuted)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                    }
                    .card()
                }

                Button("Delete this outing") { confirmDelete = true }
                    .buttonStyle(LapsyButtonStyle(kind: .outlined))
                    .foregroundStyle(Palette.destructive)
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.neutral.ignoresSafeArea())
        .confirmationDialog("Delete this outing? It can't be undone.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(run)
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        }
    }

    private var map: some View {
        let track = run.trackCoordinates
        let planned = run.plannedCoordinates
        let all = track + planned
        return Map(initialPosition: .rect(Self.rect(for: all))) {
            if planned.count > 1 {
                MapPolyline(coordinates: planned)
                    .stroke(Palette.textMuted, style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
            }
            if track.count > 1 {
                MapPolyline(coordinates: track)
                    .stroke(Palette.primary, lineWidth: 4)
            }
            if let first = track.first {
                Annotation("", coordinate: first) { dot(Palette.tertiary) }
            }
            if let last = track.last, track.count > 1 {
                Annotation("", coordinate: last) { dot(Palette.primary) }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
            .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(Palette.neutral, lineWidth: 2))
    }

    static func rect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        guard !coordinates.isEmpty else { return .world }
        let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
        let rect = line.boundingMapRect
        let padX = max(rect.width * 0.2, 400), padY = max(rect.height * 0.2, 400)
        return rect.insetBy(dx: -padX, dy: -padY)
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(label, size: 9)
            Text(value)
                .font(Typeface.headline(22))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
            Text(unit.uppercased())
                .font(Typeface.label(9))
                .foregroundStyle(Palette.textSecondary)
                .frame(height: 11, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
            .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
    }
}

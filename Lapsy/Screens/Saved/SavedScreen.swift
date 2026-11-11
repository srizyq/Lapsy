import SwiftUI
import MapKit

struct SavedScreen: View {
    @Environment(RunStore.self) private var store
    @State private var selected: SavedRoute?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if store.routes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel("Saved", color: Palette.primary)
                        Text("No saved routes yet")
                            .font(Typeface.headline(22))
                            .foregroundStyle(Palette.textPrimary)
                        Text("Found a route you like? Tap Save route in Generator and it will be here to run again.")
                            .font(Typeface.body(14))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                } else {
                    ForEach(store.routes) { saved in
                        Button { selected = saved } label: { row(saved) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(Metrics.gutter)
        }
        .sheet(item: $selected) { saved in
            SavedRouteDetail(saved: saved)
        }
    }

    private func row(_ saved: SavedRoute) -> some View {
        HStack(spacing: 12) {
            Image(systemName: saved.activity.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.primary)
                .frame(width: 40, height: 40)
                .background(Palette.well)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))

            VStack(alignment: .leading, spacing: 3) {
                Text(saved.name)
                    .font(Typeface.body(15, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text("\(saved.activity.name) · +\(Int(saved.route.ascentM.rounded())) m")
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 8)
            Text("\(Fmt.km(saved.route.distanceM)) km")
                .font(Typeface.headline(17))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
        }
        .padding(Metrics.cardPadding)
        .frame(maxWidth: .infinity)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
            .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
        .contentShape(Rectangle())
    }
}

struct SavedRouteDetail: View {
    let saved: SavedRoute

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Environment(RunStore.self) private var store
    @State private var confirmDelete = false

    var body: some View {
        let coordinates = Polyline.decode(saved.route.polyline)
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        MonoLabel(saved.activity.name, color: Palette.primary)
                        Text(saved.name)
                            .font(Typeface.headline(22))
                            .foregroundStyle(Palette.textPrimary)
                        if !saved.startName.isEmpty {
                            Text("From \(saved.startName)")
                                .font(Typeface.body(13))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(Typeface.label(11))
                        .foregroundStyle(Palette.textSecondary)
                }

                Map(initialPosition: .rect(RunDetailScreen.rect(for: coordinates))) {
                    MapPolyline(coordinates: coordinates).stroke(Palette.primary, lineWidth: 4)
                    if let first = coordinates.first {
                        Marker("Start", coordinate: first).tint(Palette.primary)
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
                    .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))

                HStack(spacing: 8) {
                    stat("Distance", Fmt.km(saved.route.distanceM), "km")
                    stat("Climb", "+\(Int(saved.route.ascentM.rounded()))", "m")
                }

                Button("Start \(saved.activity.noun)") {
                    app.session?.close()
                    app.session = RunSession(planned: PlannedRoute(
                        activity: saved.activity,
                        route: saved.route.route(),
                        profile: saved.route.profile,
                        startName: saved.startName
                    ))
                    app.tab = .liveRun
                    dismiss()
                }
                .buttonStyle(LapsyButtonStyle(kind: .primary))

                Button("Remove from saved") { confirmDelete = true }
                    .buttonStyle(LapsyButtonStyle(kind: .outlined))
                    .foregroundStyle(Palette.destructive)
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.neutral.ignoresSafeArea())
        .confirmationDialog("Remove this saved route?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                store.delete(saved)
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        }
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
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
            .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
    }
}

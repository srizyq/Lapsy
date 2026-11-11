import SwiftUI
import MapKit

struct SavedScreen: View {
    @Environment(RunStore.self) private var store
    @Environment(AppState.self) private var app
    @State private var selected: SavedRoute?
    @State private var query = ""
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", favorites = "Favorites", short = "Under 5 km", mid = "5-10 km", long = "Over 10 km", trail = "Trail"
        var id: String { rawValue }
    }

    private func matches(_ r: SavedRoute) -> Bool {
        let km = r.route.distanceM / 1000
        let passes: Bool = switch filter {
        case .all: true
        case .favorites: r.isFavorite
        case .short: km < 5
        case .mid: km >= 5 && km <= 10
        case .long: km > 10
        case .trail: r.route.surface.unpaved > 0.5
        }
        guard passes else { return false }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || r.name.lowercased().contains(q) || r.startName.lowercased().contains(q)
            || r.activity.name.lowercased().contains(q)
    }

    var body: some View {
        let shown = store.routes.filter(matches)
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
                    searchField
                    filters
                    if let featured = shown.first {
                        featuredCard(featured)
                        if shown.count > 1 {
                            HStack {
                                Text("Your saved routes")
                                    .font(Typeface.headline(18))
                                    .foregroundStyle(Palette.textPrimary)
                                Spacer()
                                MonoLabel("Newest first", size: 9)
                            }
                            .padding(.top, 6)
                            ForEach(shown.dropFirst()) { saved in
                                Button { selected = saved } label: { row(saved) }
                                    .buttonStyle(.plain)
                            }
                        }
                    } else {
                        Text("Nothing matches. Try a different filter.")
                            .font(Typeface.body(14))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }
                }
            }
            .padding(Metrics.gutter)
        }
        .sheet(item: $selected) { saved in
            SavedRouteDetail(saved: saved)
        }
    }

    // MARK: - Search and filters

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textMuted)
            TextField("Search saved routes, places...", text: $query)
                .font(Typeface.body(14))
                .foregroundStyle(Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textMuted)
                }
            }
        }
        .padding(12)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
            .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Filter.allCases) { f in
                    let count = f == .all ? "  \(store.routes.count)" : ""
                    FilterChip(
                        title: f.rawValue + count, selected: filter == f,
                        icon: f == .favorites ? "heart.fill" : (f == .trail ? "mountain.2" : nil)
                    ) { filter = f }
                }
            }
        }
    }

    // MARK: - Featured route

    private func featuredCard(_ saved: SavedRoute) -> some View {
        let route = saved.route.route()
        let points = route.profilePoints
        let history = runs(on: saved)
        let ratings = history.compactMap(\.rating)
        let amenity = AmenityFinder.shared.amenities(for: saved.route.polyline)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(saved.synced ? Palette.primary : Palette.textMuted).frame(width: 6, height: 6)
                    MonoLabel(saved.synced ? "Backed up" : "Waiting to back up", size: 9)
                }
                Spacer()
                MonoLabel(saved.createdAt.formatted(.dateTime.day().month(.abbreviated)), size: 9)
            }

            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    RouteShape(coordinates: route.coordinates, lineWidth: 3)
                        .frame(height: 150)
                    if points.count > 1 {
                        MiniElevation(points: points)
                            .frame(height: 44)
                            .padding(.top, 6)
                    }
                }
                .padding(10)
                .background(Palette.well)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
                    .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))

                Button { store.setFavorite(!saved.isFavorite, for: saved) } label: {
                    Image(systemName: saved.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(saved.isFavorite ? Palette.onPrimary : Palette.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(saved.isFavorite ? Palette.primary : Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                        .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
                            .strokeBorder(Palette.hairline, lineWidth: saved.isFavorite ? 0 : Metrics.hairline))
                }
                .padding(8)
                .accessibilityLabel(saved.isFavorite ? "Remove from favorites" : "Add to favorites")
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(saved.name)
                        .font(Typeface.headline(22))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                    Text(subtitle(saved))
                        .font(Typeface.body(12))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.1f", saved.route.distanceM / 1000))
                        .font(Typeface.headline(32))
                        .foregroundStyle(Palette.textPrimary)
                        .monospacedDigit()
                    MonoLabel("Kilometers", size: 8)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Tag(text: "+\(Int(saved.route.ascentM.rounded())) m climb", icon: "arrow.up.right")
                    if let a = amenity, a.water > 0 { Tag(text: "Water (\(a.water))", icon: "drop") }
                    if let a = amenity, a.toilets > 0 { Tag(text: "Restrooms (\(a.toilets))", icon: "figure.stand") }
                    if saved.route.surface.paved >= 0.6 { Tag(text: "Mostly paved", icon: "road.lanes") }
                    if saved.route.surface.unpaved >= 0.4 { Tag(text: "Trail sections", icon: "mountain.2") }
                    if !history.isEmpty { Tag(text: "Done \(history.count)x", icon: "checkmark") }
                    if !ratings.isEmpty {
                        let avg = Double(ratings.reduce(0, +)) / Double(ratings.count)
                        Tag(text: String(format: "%.1f rating", avg), icon: "star.fill")
                    }
                }
            }

            HStack(spacing: 8) {
                Button { start(saved) } label: {
                    Label("Start now", systemImage: "play.fill")
                }
                .buttonStyle(LapsyButtonStyle(kind: .inverted))
                Button { selected = saved } label: { Text("Details") }
                    .buttonStyle(LapsyButtonStyle(kind: .outlined))
            }
        }
        .card()
        .task(id: saved.id) { await AmenityFinder.shared.load(polyline: saved.route.polyline) }
    }

    private func subtitle(_ saved: SavedRoute) -> String {
        var parts = [saved.activity.name]
        if !saved.startName.isEmpty { parts.append("from \(saved.startName)") }
        return parts.joined(separator: " · ")
    }

    /// Outings that followed this exact route.
    private func runs(on saved: SavedRoute) -> [SavedRun] {
        store.runs.filter { $0.plannedPolyline == saved.route.polyline }
    }

    private func start(_ saved: SavedRoute) {
        app.session?.close()
        app.session = RunSession(planned: PlannedRoute(
            activity: saved.activity, route: saved.route.route(),
            profile: saved.route.profile, startName: saved.startName
        ))
        app.tab = .liveRun
    }

    // MARK: - List row

    private func row(_ saved: SavedRoute) -> some View {
        let ratings = runs(on: saved).compactMap(\.rating)
        return HStack(spacing: 12) {
            RouteShape(coordinates: Polyline.decode(saved.route.polyline))
                .frame(width: 56, height: 56)
                .background(Palette.well)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))

            VStack(alignment: .leading, spacing: 4) {
                Text(saved.name)
                    .font(Typeface.body(15, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text("\(Fmt.km(saved.route.distanceM)) km · +\(Int(saved.route.ascentM.rounded())) m · \(saved.createdAt.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(Typeface.label(10))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if saved.isFavorite { Tag(text: "Favorite", icon: "heart.fill") }
                    if !ratings.isEmpty {
                        let avg = Double(ratings.reduce(0, +)) / Double(ratings.count)
                        Tag(text: String(format: "%.1f", avg), icon: "star.fill")
                    }
                    Tag(text: saved.route.surface.unpaved > 0.5 ? "Trail" : "Paved")
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textMuted)
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

/// A small elevation outline with no axes.
struct MiniElevation: View {
    let points: [ProfilePoint]

    var body: some View {
        let low = points.map(\.elevation).min() ?? 0
        let high = points.map(\.elevation).max() ?? 1
        let span = max(high - low, 1)
        let maxKm = max(points.last?.km ?? 1, 0.001)
        Canvas { context, size in
            var line = Path()
            for (i, p) in points.enumerated() {
                let pt = CGPoint(x: p.km / maxKm * size.width,
                                 y: size.height - (p.elevation - low) / span * (size.height - 4) - 2)
                i == 0 ? line.move(to: pt) : line.addLine(to: pt)
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [Palette.primary.opacity(0.3), Palette.primary.opacity(0)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(Palette.primary), lineWidth: 1.5)
        }
    }
}

struct SavedRouteDetail: View {
    let saved: SavedRoute

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Environment(RunStore.self) private var store
    @State private var confirmDelete = false
    @State private var gpxItem: ShareItem?

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

                Button("Export GPX file") {
                    if let url = try? GPX.file(name: saved.name, route: saved.route) { gpxItem = ShareItem(url: url) }
                }
                .buttonStyle(LapsyButtonStyle(kind: .outlined))

                ShareRouteButton(id: saved.id, name: saved.name, activityId: saved.activityId, route: { saved.route })

                Button("Remove from saved") { confirmDelete = true }
                    .buttonStyle(LapsyButtonStyle(kind: .outlined))
                    .foregroundStyle(Palette.destructive)
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.neutral.ignoresSafeArea())
        .sheet(item: $gpxItem) { item in ActivitySheet(items: [item.url]).presentationDetents([.medium, .large]) }
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

import SwiftUI
import MapKit

struct GeneratorScreen: View {
    @Environment(AppState.self) private var app
    @Environment(RunStore.self) private var store
    private var model: GeneratorModel { app.generator }
    private var bound: Bindable<GeneratorModel> { Bindable(app.generator) }
    @State private var camera: MapCameraPosition = .automatic
    @State private var showStartSheet = false
    @State private var showDestinationSheet = false
    @State private var gpxItem: ShareItem?
    @State private var gpxError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                activityRow
                mapPanel
                if model.activity.canRoute {
                    controlsPanel
                } else {
                    trackOnlyCard
                }
                if let route = model.route {
                    routeDetailsCard(route)
                }
                if let error = model.errorText {
                    Text(error)
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.destructive)
                        .card()
                } else if let note = model.noteText {
                    Text(note)
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.textSecondary)
                        .card()
                }
                if model.route != nil || !model.activity.canRoute {
                    startButton
                }
                if let route = model.route, model.activity.canRoute {
                    exportCard(route)
                }
            }
            .padding(Metrics.gutter)
        }
        .sheet(item: $gpxItem) { item in
            ActivitySheet(items: [item.url]).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showDestinationSheet) {
            StartPointSheet(location: app.location, title: "Where to?", showCurrent: false) { picked, _ in
                model.destination = picked
            }
        }
        .sheet(isPresented: $showStartSheet) {
            StartPointSheet(location: app.location) { picked, isCurrent in
                model.start = picked
                model.usingCurrentLocation = isCurrent
            }
        }
        .onAppear {
            if model.usingCurrentLocation, let c = app.location.coordinate {
                model.start = StartPoint(name: "Current location", coordinate: c)
            }
            recenter()
            app.location.request()
            if model.autoGenerate {
                model.autoGenerate = false
                Task { await generate() }
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["LAPSY_AUTOGEN"] == "1" {
                Task {
                    await generate()
                    debugAfterGenerate()
                }
            }
            #endif
        }
        .onChange(of: app.location.coordinate?.latitude) { _, _ in
            guard model.usingCurrentLocation, let c = app.location.coordinate else { return }
            model.start = StartPoint(name: "Current location", coordinate: c)
            recenter()   // in the same update, so the map never shows the old spot
        }
        .onChange(of: model.start) { _, _ in
            model.reset()
            recenter()
        }
        .onChange(of: model.activity) { _, _ in model.reset() }
        .onChange(of: model.pathType) { _, _ in model.reset() }
        .onChange(of: model.avoidSteps) { _, _ in model.reset() }
        .onChange(of: model.avoidBusyRoads) { _, _ in model.reset() }
        .onChange(of: model.preferGreen) { _, _ in model.reset() }
        .onChange(of: model.elevationBias) { _, _ in model.reset() }
        .onChange(of: model.shape) { _, _ in model.reset() }
        .onChange(of: model.destination) { _, _ in model.reset() }
    }

    // MARK: - Activity

    private static let quickActivityIds = ["walk", "run", "trailrun", "hike"]

    private var activityRow: some View {
        let quick = Self.quickActivityIds.compactMap { id in Activity.all.first { $0.id == id } }
        let other = !quick.contains(model.activity)
        return HStack(spacing: 8) {
            ForEach(quick) { activity in
                activityTile(activity)
            }
            Menu {
                ForEach(ActivityGroup.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(Activity.all.filter { $0.group == group }) { activity in
                            Button {
                                model.setActivity(activity)
                            } label: {
                                Label(activity.name + (activity.canRoute ? "" : " (GPS only)"),
                                      systemImage: Self.validSymbol(activity.icon))
                            }
                        }
                    }
                }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: other ? Self.validSymbol(model.activity.icon) : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                    Text(other ? model.activity.name.uppercased() : "MORE")
                        .font(Typeface.label(9, weight: .bold))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(other ? Palette.primary : Palette.textSecondary)
                .frame(width: 62)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 12)
                .background(other ? Palette.surface : Palette.well)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.corner)
                        .strokeBorder(other ? Palette.primary : Palette.hairline, lineWidth: Metrics.hairline)
                )
            }
            .accessibilityLabel("All activities")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func activityTile(_ activity: Activity) -> some View {
        let selected = activity == model.activity
        return Button {
            model.setActivity(activity)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: Self.validSymbol(activity.icon))
                    .font(.system(size: 14, weight: .semibold))
                Text(activity.name.uppercased())
                    .font(Typeface.label(9, weight: .bold))
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? Palette.primary : Palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selected ? Palette.surface : Palette.well)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.corner)
                    .strokeBorder(selected ? Palette.primary : Palette.hairline, lineWidth: Metrics.hairline)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Circle().fill(Palette.primary).frame(width: 5, height: 5).padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private static func validSymbol(_ name: String) -> String {
        UIImage(systemName: name) == nil ? "figure.mixed.cardio" : name
    }

    // MARK: - Map and numbers

    private var mapPanel: some View {
        VStack(spacing: 0) {
            map
                .frame(height: 280)
                .overlay(alignment: .bottom) { startOverlay }
            Rectangle().fill(Palette.hairline).frame(height: Metrics.hairline)
            statsStrip
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
        )
    }

    private var map: some View {
        Map(position: $camera) {
            Marker("Start", coordinate: model.start.coordinate)
                .tint(Palette.primary)
            if model.shape == .pointToPoint, let end = model.destination {
                Marker("End", coordinate: end.coordinate)
                    .tint(Palette.secondary)
            }
            if let route = model.route {
                MapPolyline(coordinates: route.coordinates)
                    .stroke(Palette.primary, lineWidth: 4)
            }
            if let i = model.scrubIndex, model.profilePoints.indices.contains(i) {
                Annotation("", coordinate: model.profilePoints[i].coordinate) {
                    Circle()
                        .fill(Palette.tertiary)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Palette.neutral, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .overlay {
            if let message = startUnresolved {
                ZStack {
                    Palette.well
                    Text(message)
                        .font(Typeface.body(14))
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(24)
                }
            }
        }
    }

    /// Why there is no real start point yet, or nil once there is one.
    private var startUnresolved: String? {
        guard model.usingCurrentLocation, app.location.coordinate == nil else { return nil }
        return app.location.denied
            ? "Location is off for Lapsy. Tap Change to pick where to start, or turn location on in Settings."
            : "Finding your location..."
    }

    private var startOverlay: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 14))
                .foregroundStyle(Palette.primary)
            VStack(alignment: .leading, spacing: 3) {
                MonoLabel("Start point", size: 9)
                Text(startUnresolved == nil ? model.start.name : (app.location.denied ? "Not set" : "Finding your location..."))
                    .font(Typeface.headline(15))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button {
                showStartSheet = true
            } label: {
                HStack(spacing: 5) {
                    Text("CHANGE")
                    Image(systemName: "pencil")
                }
                .font(Typeface.label(10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Palette.well)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.corner)
                        .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
                )
            }
        }
        .padding(12)
        .background(Palette.neutral.opacity(0.88))
    }

    private var statsStrip: some View {
        let route = model.route
        let km = route.map { String(format: "%.1f", $0.distanceM / 1000) } ?? "--"
        let time = route.map { Self.duration($0.durationS * model.activity.paceFactor) } ?? "--"
        let climb = route.map { String(format: "+%.0f", $0.ascentM) } ?? "--"
        let paved = route.map { "\(Int(($0.surface.paved * 100).rounded()))%" } ?? "--"
        return HStack(spacing: 0) {
            stripCell("Distance", km, "km")
            stripDivider
            stripCell("Est. time", time, "")
            stripDivider
            stripCell("Climb", climb, "m")
            stripDivider
            stripCell("Paved", paved, "")
        }
    }

    private var stripDivider: some View {
        Rectangle().fill(Palette.hairline).frame(width: Metrics.hairline)
    }

    private func stripCell(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 4) {
            MonoLabel(label, size: 8)
            Text(value)
                .font(Typeface.headline(20))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit.isEmpty ? " " : unit.uppercased())
                .font(Typeface.label(8))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Controls

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Palette.primary).frame(width: 5, height: 5)
                MonoLabel("Tweak your route", size: 10)
            }

            if model.shape == .pointToPoint {
                destinationBox
            } else {
                distanceBox
            }

            MonoLabel("Route shape", size: 9)
            HStack(spacing: 8) {
                ForEach(RouteKind.allCases) { kind in
                    choiceChip(kind.rawValue, selected: model.shape == kind, enabled: true) {
                        model.shape = kind
                    }
                }
            }

            MonoLabel("Path type", size: 9)
            HStack(spacing: 8) {
                ForEach(PathType.allCases) { type in
                    choiceChip(type.rawValue, selected: model.pathType == type, enabled: true) {
                        model.pathType = type
                    }
                }
            }

            MonoLabel("Preferences", size: 9)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                toggleTile("Avoid steps", icon: "figure.stairs", isOn: bound.avoidSteps)
                toggleTile("Avoid busy roads", icon: "car", isOn: bound.avoidBusyRoads)
                toggleTile("Greener route", icon: "tree", isOn: bound.preferGreen)
                biasTile
            }

            Button {
                Task { await generate() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(model.loading
                         ? "Finding your route..."
                         : (model.shape == .pointToPoint ? "Find route"
                            : (model.result == nil ? "Make a route" : "Make another route")))
                }
            }
            .buttonStyle(LapsyButtonStyle(kind: .outlined))
            .disabled(model.loading || startUnresolved != nil
                      || (model.shape == .pointToPoint && model.destination == nil))
        }
        .card()
    }

    private var distanceBox: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel("Distance", size: 9)
                Spacer()
                Text("\(model.lengthKm, specifier: "%05.2f")")
                    .font(Typeface.headline(30))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
                Text("KM")
                    .font(Typeface.label(10))
                    .foregroundStyle(Palette.textSecondary)
            }
            Slider(value: bound.lengthKm, in: model.lengthRange, step: 0.5)
                .tint(Palette.primary)
            HStack {
                Text("MIN \(Int(model.lengthRange.lowerBound)) KM")
                Spacer()
                Text("MAX \(Int(model.lengthRange.upperBound)) KM")
            }
            .font(Typeface.label(9))
            .foregroundStyle(Palette.textMuted)
        }
        .padding(12)
        .background(Palette.well)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
        )
    }

    private var destinationBox: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                MonoLabel("Going to", size: 9)
                Text(model.destination?.name ?? "Not chosen yet")
                    .font(Typeface.headline(16))
                    .foregroundStyle(model.destination == nil ? Palette.textMuted : Palette.textPrimary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                showDestinationSheet = true
            } label: {
                Text(model.destination == nil ? "CHOOSE" : "CHANGE")
                    .font(Typeface.label(10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Palette.onPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Palette.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            }
        }
        .padding(12)
        .background(Palette.well)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
        )
    }

    private func choiceChip(
        _ title: String, selected: Bool, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected { Circle().fill(Palette.primary).frame(width: 5, height: 5) }
                Text(title.uppercased())
                    .font(Typeface.label(9, weight: .bold))
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(selected ? Palette.surface : Palette.well)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.corner)
                    .strokeBorder(selected ? Palette.primary : Palette.hairline, lineWidth: Metrics.hairline)
            )
            .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func toggleTile(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            tileLabel(title, icon: icon, active: isOn.wrappedValue)
        }
        .buttonStyle(.plain)
    }

    /// Tap to cycle: any, flatter, hillier.
    private var biasTile: some View {
        let all = ElevationBias.allCases
        return Button {
            let next = all[(all.firstIndex(of: model.elevationBias)! + 1) % all.count]
            model.elevationBias = next
        } label: {
            tileLabel(model.elevationBias == .any ? "Hills: any" : "Hills: \(model.elevationBias.rawValue.lowercased())",
                      icon: "chart.line.uptrend.xyaxis", active: model.elevationBias != .any)
        }
        .buttonStyle(.plain)
    }

    private func tileLabel(_ title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(active ? Palette.primary : Palette.textMuted)
                .frame(width: 18, height: 18)
            Text(title.uppercased())
                .font(Typeface.label(9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(active ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2)
                .fill(active ? Palette.primary : Palette.surface)
                .frame(width: 10, height: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(active ? .clear : Palette.hairline, lineWidth: Metrics.hairline)
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(Palette.well)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
        )
    }

    private var trackOnlyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Tracking only", color: Palette.primary)
            Text("No generated route for \(model.activity.name.lowercased())")
                .font(Typeface.headline(18))
                .foregroundStyle(Palette.textPrimary)
            Text("Lapsy will record your GPS track, time, distance and energy, and save the workout to Apple Health.")
                .font(Typeface.body(13))
                .foregroundStyle(Palette.textSecondary)
        }
        .card()
    }

    // MARK: - Route details

    private func routeDetailsCard(_ route: GeneratedRoute) -> some View {
        let steepest = model.profilePoints.map(\.grade).max { abs($0) < abs($1) }
        let destinationName = model.shape == .pointToPoint ? model.destination?.name : nil
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Image(systemName: "mountain.2")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.primary)
                        MonoLabel("Your route", size: 10)
                    }
                    Text("\(model.activity.name) \(model.shape.noun)")
                        .font(Typeface.headline(20))
                        .foregroundStyle(Palette.textPrimary)
                    Text(destinationName.map { "to \($0)" } ?? "from \(model.start.name)")
                        .font(Typeface.body(12))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if let steepest, abs(steepest) >= 1 {
                    Text("STEEPEST \(Int(abs(steepest).rounded()))%")
                        .font(Typeface.label(9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Palette.well)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.corner)
                                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
                        )
                }
            }

            HStack {
                routeTags(route)
                Spacer(minLength: 0)
                if model.candidates.count > 1 {
                    Button {
                        model.nextCandidate()
                    } label: {
                        Text("ANOTHER \(model.selected + 1)/\(model.candidates.count)")
                            .font(Typeface.label(10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Palette.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: Metrics.corner)
                                    .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
                            )
                    }
                }
            }

            MonoLabel("Elevation", size: 9)
            ElevationChart(points: model.profilePoints, scrub: bound.scrubIndex)
                .frame(height: 150)

            MonoLabel("Surface", size: 9)
            surfaceBar(route.surface)
            surfaceLegend(route.surface)

            #if DEBUG
            Text(String(
                format: "debug: off target %.0f%%  retraced %.0f%%  roundness %.2f  busy %.0f%%  tried %d",
                route.score.distanceError * 100, route.score.overlap * 100,
                route.score.roundness, route.busyShare * 100, model.result?.requested ?? 0
            ))
            .font(Typeface.label(9))
            .foregroundStyle(Palette.textMuted)
            #endif
        }
        .card()
        .task(id: Polyline.encode(route.coordinates)) {
            await AmenityFinder.shared.load(polyline: Polyline.encode(route.coordinates))
        }
    }

    /// Tags about the route. Water and toilets come from OpenStreetMap and appear once found.
    private func routeTags(_ route: GeneratedRoute) -> some View {
        let amenity = AmenityFinder.shared.amenities(for: Polyline.encode(route.coordinates))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if route.surface.paved >= 0.6 { Tag(text: "Mostly paved", icon: "road.lanes") }
                if route.surface.unpaved >= 0.4 { Tag(text: "Trail sections", icon: "mountain.2") }
                if let a = amenity, a.water > 0 { Tag(text: "Water (\(a.water))", icon: "drop") }
                if let a = amenity, a.toilets > 0 { Tag(text: "Restrooms (\(a.toilets))", icon: "figure.stand") }
            }
        }
    }

    private func surfaceBar(_ mix: SurfaceMix) -> some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let usable = geo.size.width - gap * 2
            HStack(spacing: gap) {
                Rectangle().fill(Palette.tertiary).frame(width: max(0, usable * mix.paved))
                Rectangle().fill(Palette.secondary).frame(width: max(0, usable * mix.unpaved))
                Rectangle().fill(Palette.hairline).frame(width: max(0, usable * mix.unknown))
            }
        }
        .frame(height: 6)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private func surfaceLegend(_ mix: SurfaceMix) -> some View {
        HStack(spacing: 14) {
            legend(Palette.tertiary, "Paved", mix.paved)
            legend(Palette.secondary, "Path / dirt", mix.unpaved)
            if mix.unknown > 0.05 { legend(Palette.hairline, "Unknown", mix.unknown) }
        }
    }

    private func legend(_ color: Color, _ title: String, _ share: Double) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            Text("\(title) \(Int((share * 100).rounded()))%")
                .font(Typeface.label(9))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    // MARK: - Export

    private func exportCard(_ route: GeneratedRoute) -> some View {
        let name = "\(model.activity.name) \(String(format: "%.1f", route.distanceM / 1000)) km"
        return VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Save & export")
            HStack(spacing: 8) {
                saveRouteButton(route)
                Button {
                    do {
                        let url = try GPX.file(name: name, route: StoredRoute(route, profile: model.profile))
                        gpxItem = ShareItem(url: url)
                        gpxError = nil
                    } catch {
                        gpxError = "Couldn't make the file. Try again."
                    }
                } label: { Text("GPX file") }
                    .buttonStyle(LapsyButtonStyle(kind: .outlined))
            }
            ShareRouteButton(
                name: "\(model.activity.name) · \(String(format: "%.1f", route.distanceM / 1000)) km",
                activityId: model.activity.id,
                route: { StoredRoute(route, profile: model.profile) }
            )
            if let gpxError {
                Text(gpxError)
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.destructive)
            }
        }
        .card()
    }

    // MARK: - Start run

    private var startButton: some View {
        Button {
            startRun()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                Text(startTitle)
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(LapsyButtonStyle(kind: .primary))
    }

    private var startTitle: String {
        if let route = model.route, model.activity.canRoute {
            return "Start \(model.activity.noun) · \(String(format: "%.1f", route.distanceM / 1000)) km"
        }
        return "Start \(model.activity.noun)"
    }

    private func isSaved(_ route: GeneratedRoute) -> Bool {
        store.routes.contains {
            $0.activityId == model.activity.id
                && abs($0.route.distanceM - route.distanceM) < 0.5
                && $0.route.polyline.hasPrefix(Polyline.encode(Array(route.coordinates.prefix(8))))
        }
    }

    private func saveRouteButton(_ route: GeneratedRoute) -> some View {
        let saved = isSaved(route)
        return Button {
            store.add(SavedRoute(
                name: "\(model.activity.name) · \(String(format: "%.1f", route.distanceM / 1000)) km · \(model.start.name)",
                activityId: model.activity.id,
                startName: model.start.name,
                createdAt: Date(),
                route: StoredRoute(route, profile: model.profile)
            ))
        } label: {
            Text(saved ? "Saved" : "Save route")
        }
        .buttonStyle(LapsyButtonStyle(kind: .outlined))
        .disabled(saved)
    }

    // MARK: - Helpers

    private func generate() async {
        await model.generate()
        if let route = model.route { fit(route) }
    }

    private func startRun() {
        app.session?.close()
        app.session = RunSession(planned: PlannedRoute(
            activity: model.activity,
            route: model.activity.canRoute ? model.route : nil,
            profile: model.profile,
            startName: model.start.name
        ))
        app.tab = .liveRun
    }

    #if DEBUG
    /// Test hooks: LAPSY_DUMP_ROUTE=/path writes the route as [[lat, lon]] JSON,
    /// LAPSY_AUTORUN=1 starts the run straight away.
    private func debugAfterGenerate() {
        let env = ProcessInfo.processInfo.environment
        if let path = env["LAPSY_DUMP_ROUTE"], let route = model.route {
            let json = route.coordinates.map { [$0.latitude, $0.longitude] }
            if let data = try? JSONSerialization.data(withJSONObject: json) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        if env["LAPSY_AUTORUN"] == "1" { startRun() }
    }
    #endif

    private func recenter() {
        camera = .region(
            MKCoordinateRegion(
                center: model.start.coordinate,
                latitudinalMeters: 3000,
                longitudinalMeters: 3000
            )
        )
    }

    private func fit(_ route: GeneratedRoute) {
        let line = MKPolyline(coordinates: route.coordinates, count: route.coordinates.count)
        let rect = line.boundingMapRect
        let padded = rect.insetBy(dx: -rect.width * 0.25, dy: -rect.height * 0.25)
        withAnimation { camera = .rect(padded) }
    }

    private static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

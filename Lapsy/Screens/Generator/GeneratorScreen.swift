import SwiftUI
import MapKit

struct GeneratorScreen: View {
    @Environment(AppState.self) private var app
    @Environment(RunStore.self) private var store
    @State private var model = GeneratorModel()
    @State private var camera: MapCameraPosition = .automatic
    @State private var showStartSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                activityCard
                mapCard
                startCard
                if model.activity.canRoute {
                    parametersCard
                } else {
                    trackOnlyCard
                }
                if let route = model.route {
                    previewCard(route)
                }
                if let error = model.errorText {
                    Text(error)
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.destructive)
                        .card()
                }
                if model.route != nil || !model.activity.canRoute {
                    startButton
                }
                if let route = model.route, model.activity.canRoute {
                    saveRouteButton(route)
                }
            }
            .padding(Metrics.gutter)
        }
        .sheet(isPresented: $showStartSheet) {
            StartPointSheet(location: app.location) { picked, isCurrent in
                model.start = picked
                model.usingCurrentLocation = isCurrent
            }
        }
        .onAppear {
            recenter()
            app.location.request()
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
    }

    // MARK: - Activity

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Activity")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Activity.all) { activity in
                        activityChip(activity)
                    }
                }
            }
        }
        .card()
    }

    private func activityChip(_ activity: Activity) -> some View {
        let selected = activity == model.activity
        return Button {
            model.setActivity(activity)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: Self.validSymbol(activity.icon))
                    .font(.system(size: 13, weight: .medium))
                Text(activity.name)
                    .font(Typeface.body(13, weight: .medium))
                if !activity.canRoute {
                    Text("GPS")
                        .font(Typeface.label(8, weight: .bold))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(selected ? Palette.onPrimary : Palette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(selected ? Palette.primary : Palette.well)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.corner)
                    .strokeBorder(selected ? .clear : Palette.hairline, lineWidth: Metrics.hairline)
            )
        }
        .buttonStyle(.plain)
    }

    private static func validSymbol(_ name: String) -> String {
        UIImage(systemName: name) == nil ? "figure.mixed.cardio" : name
    }

    // MARK: - Map

    private var mapCard: some View {
        Map(position: $camera) {
            Marker("Start", coordinate: model.start.coordinate)
                .tint(Palette.primary)
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
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
        )
    }

    // MARK: - Start point

    /// Why there is no real start point yet, or nil once there is one.
    private var startUnresolved: String? {
        guard model.usingCurrentLocation, app.location.coordinate == nil else { return nil }
        return app.location.denied
            ? "Location is off for Lapsy. Tap Change to pick where to start, or turn location on in Settings."
            : "Finding your location..."
    }

    private var startCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                MonoLabel("Start point")
                Text(startUnresolved == nil ? model.start.name : (app.location.denied ? "Not set" : "Finding your location..."))
                    .font(Typeface.body(15, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                showStartSheet = true
            } label: {
                Text("CHANGE")
                    .font(Typeface.label(10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.corner)
                            .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
                    )
            }
        }
        .card()
    }

    // MARK: - Parameters

    private var parametersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel("Distance")
                Spacer()
                Text("\(model.lengthKm, specifier: "%.1f")")
                    .font(Typeface.headline(30))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
                Text("KM")
                    .font(Typeface.label(11))
                    .foregroundStyle(Palette.textSecondary)
            }
            Slider(value: $model.lengthKm, in: model.lengthRange, step: 0.5)
                .tint(Palette.primary)

            MonoLabel("Route shape")
            HStack(spacing: 8) {
                choiceChip("Loop", selected: true, enabled: true) {}
                choiceChip("Out & back", selected: false, enabled: false) {}
                choiceChip("Point to point", selected: false, enabled: false) {}
            }

            MonoLabel("Path type")
            HStack(spacing: 8) {
                ForEach(PathType.allCases) { type in
                    choiceChip(type.rawValue, selected: model.pathType == type, enabled: true) {
                        model.pathType = type
                    }
                }
            }

            MonoLabel("Avoid")
            toggleRow("Steps", isOn: $model.avoidSteps)

            Button {
                Task { await generate() }
            } label: {
                Text(model.loading
                     ? "Finding best loop..."
                     : (model.result == nil ? "Generate route" : "Generate new route"))
            }
            .buttonStyle(LapsyButtonStyle(kind: .primary))
            .disabled(model.loading || startUnresolved != nil)
        }
        .card()
    }

    private func choiceChip(
        _ title: String, selected: Bool, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typeface.body(12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? Palette.onPrimary : Palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? Palette.primary : Palette.well)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.corner)
                        .strokeBorder(selected ? .clear : Palette.hairline, lineWidth: Metrics.hairline)
                )
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack {
                Text(title)
                    .font(Typeface.body(14))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(isOn.wrappedValue ? Palette.primary : Palette.well)
                    .frame(width: 18, height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(isOn.wrappedValue ? .clear : Palette.hairline, lineWidth: Metrics.hairline)
                    )
                    .overlay {
                        if isOn.wrappedValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.onPrimary)
                        }
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
        .buttonStyle(.plain)
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

    // MARK: - Preview

    private func previewCard(_ route: GeneratedRoute) -> some View {
        let km = route.distanceM / 1000
        let kcal = model.activity.kcalPerKmPerKg * 70 * km
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                MonoLabel("Route preview", color: Palette.primary)
                Spacer()
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

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                stat("Distance", String(format: "%.2f km", km))
                stat("Est. time", Self.duration(route.durationS * model.activity.paceFactor))
                stat("Climb", String(format: "+%.0f m", route.ascentM))
                stat("Energy (est.)", String(format: "~%.0f kcal", kcal))
            }

            MonoLabel("Elevation")
            ElevationChart(points: model.profilePoints, scrub: $model.scrubIndex)
                .frame(height: 150)

            MonoLabel("Surface")
            surfaceBar(route.surface)
            surfaceLegend(route.surface)

            #if DEBUG
            Text(String(
                format: "debug: off target %.0f%%  retraced %.0f%%  roundness %.2f  tried %d",
                route.score.distanceError * 100, route.score.overlap * 100,
                route.score.roundness, model.result?.requested ?? 0
            ))
            .font(Typeface.label(9))
            .foregroundStyle(Palette.textMuted)
            #endif
        }
        .card()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(label, size: 9)
            Text(value)
                .font(Typeface.headline(17))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.well)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
        )
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

    // MARK: - Start run

    private var startButton: some View {
        Button {
            startRun()
        } label: {
            Text("Start \(model.activity.noun)")
        }
        .buttonStyle(LapsyButtonStyle(kind: .primary))
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

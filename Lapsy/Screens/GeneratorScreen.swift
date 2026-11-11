import SwiftUI
import MapKit

/// Route-generation test screen. The real Generator UI replaces this in step 3;
/// for now it proves loops can be requested, scored, ranked and drawn in
/// different places and for different activities.
struct TestLocation: Identifiable, Hashable {
    let name: String
    let latitude: Double
    let longitude: Double
    var id: String { name }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static let all = [
        TestLocation(name: "SF Marina (grid)", latitude: 37.8030, longitude: -122.4375),
        TestLocation(name: "Golden Gate Park", latitude: 37.7694, longitude: -122.4862),
        TestLocation(name: "Marin trails", latitude: 37.8575, longitude: -122.5380),
        TestLocation(name: "Central Park NYC", latitude: 40.7812, longitude: -73.9665),
        TestLocation(name: "Richmond Park London", latitude: 51.4453, longitude: -0.2840),
    ]
}

extension RoutingProfile {
    var title: String {
        switch self {
        case .footWalking: "Walk / run"
        case .footHiking: "Hike"
        case .cyclingRegular: "Bike"
        case .cyclingRoad: "Road bike"
        case .cyclingMountain: "Mountain bike"
        }
    }
}

struct GeneratorScreen: View {
    @State private var location = TestLocation.all[0]
    @State private var profile: RoutingProfile = .footWalking
    @State private var lengthKm: Double = 5
    @State private var round = 0
    @State private var result: GenerationResult?
    @State private var loading = false
    @State private var errorText: String?
    @State private var camera: MapCameraPosition = .automatic

    private var route: GeneratedRoute? { result?.best }

    #if DEBUG
    /// Test hooks so a place, activity and auto-generate can be set at launch:
    /// SIMCTL_CHILD_LAPSY_PLACE=2 SIMCTL_CHILD_LAPSY_PROFILE=foot-hiking SIMCTL_CHILD_LAPSY_AUTOGEN=1
    init() {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["LAPSY_PLACE"], let i = Int(raw), TestLocation.all.indices.contains(i) {
            _location = State(initialValue: TestLocation.all[i])
        }
        if let raw = env["LAPSY_PROFILE"], let p = RoutingProfile(rawValue: raw) {
            _profile = State(initialValue: p)
        }
        if let raw = env["LAPSY_KM"], let km = Double(raw) {
            _lengthKm = State(initialValue: km)
        }
    }
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                mapCard
                controlsCard
                if let result { statsCard(result) }
                if let errorText {
                    Text(errorText)
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.destructive)
                        .card()
                }
            }
            .padding(Metrics.gutter)
        }
        .onAppear {
            recenter()
            #if DEBUG
            if ProcessInfo.processInfo.environment["LAPSY_AUTOGEN"] == "1" {
                Task { await generate() }
            }
            #endif
        }
    }

    // MARK: - Map

    private var mapCard: some View {
        Map(position: $camera) {
            Marker("Start", coordinate: location.coordinate)
                .tint(Palette.primary)
            if let route {
                MapPolyline(coordinates: route.coordinates)
                    .stroke(Palette.primary, lineWidth: 4)
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
        )
    }

    // MARK: - Controls

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                menu("Place", selection: $location, options: TestLocation.all) { $0.name }
                menu("Activity", selection: $profile, options: RoutingProfile.allCases) { $0.title }
            }
            .onChange(of: location) { _, _ in reset(); recenter() }
            .onChange(of: profile) { _, _ in reset() }

            HStack {
                MonoLabel("Distance")
                Spacer()
                Text("\(lengthKm, specifier: "%.1f") km")
                    .font(Typeface.headline(20))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
            }
            Slider(value: $lengthKm, in: 2...20, step: 0.5)
                .tint(Palette.primary)

            Button {
                Task { await generate() }
            } label: {
                Text(loading ? "Finding best loop..." :(result == nil ? "Generate loop" : "Generate another"))
            }
            .buttonStyle(LapsyButtonStyle(kind: .primary))
            .disabled(loading)
        }
        .card()
    }

    private func menu<T: Hashable>(
        _ label: String,
        selection: Binding<T>,
        options: [T],
        title: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel(label, size: 9)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(title(option)) { selection.wrappedValue = option }
                }
            } label: {
                HStack {
                    Text(title(selection.wrappedValue))
                        .font(Typeface.body(13, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.textMuted)
                }
                .padding(10)
                .background(Palette.well)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.corner)
                        .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats

    private func statsCard(_ result: GenerationResult) -> some View {
        let route = result.best
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                stat("Distance", String(format: "%.2f km", route.distanceM / 1000))
                stat("Est. time", Self.duration(route.durationS))
                stat("Climb", String(format: "+%.0f m", route.ascentM))
            }
            HStack(spacing: 8) {
                stat("Off target", String(format: "%.0f%%", route.score.distanceError * 100))
                stat("Retraced", String(format: "%.0f%%", route.score.overlap * 100))
                stat("Roundness", String(format: "%.2f", route.score.roundness))
            }

            MonoLabel("Surface")
            surfaceBar(route.surface)
            Text(surfaceCaption(route.surface))
                .font(Typeface.label(10))
                .foregroundStyle(Palette.textSecondary)

            MonoLabel("Candidates (\(result.ranked.count) of \(result.requested))"
                + (result.corrected ? " - length corrected" : ""))
            ForEach(Array(result.ranked.enumerated()), id: \.offset) { index, candidate in
                HStack {
                    Text(index == 0 ? "BEST" : "#\(index + 1)")
                        .font(Typeface.label(10, weight: .bold))
                        .foregroundStyle(index == 0 ? Palette.primary : Palette.textMuted)
                        .frame(width: 40, alignment: .leading)
                    Text(String(
                        format: "%.2f km  retrace %.0f%%  round %.2f  score %.2f",
                        candidate.distanceM / 1000,
                        candidate.score.overlap * 100,
                        candidate.score.roundness,
                        candidate.score.total
                    ))
                    .font(Typeface.label(10))
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
                }
            }
        }
        .card()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(label, size: 9)
            Text(value)
                .font(Typeface.headline(16))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
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
            HStack(spacing: 2) {
                segment(mix.paved, Palette.primary, geo.size.width)
                segment(mix.unpaved, Palette.secondary, geo.size.width)
                segment(mix.unknown, Palette.hairline, geo.size.width)
            }
        }
        .frame(height: 6)
    }

    private func segment(_ share: Double, _ color: Color, _ width: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(0, width * share))
    }

    private func surfaceCaption(_ mix: SurfaceMix) -> String {
        String(
            format: "%.0f%% paved / %.0f%% path or dirt / %.0f%% unknown",
            mix.paved * 100, mix.unpaved * 100, mix.unknown * 100
        )
    }

    private static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    // MARK: - Actions

    private func reset() {
        result = nil
        errorText = nil
        round = 0
    }

    private func recenter() {
        camera = .region(
            MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 3000,
                longitudinalMeters: 3000
            )
        )
    }

    private func generate() async {
        loading = true
        errorText = nil
        if result != nil { round += 1 }
        defer { loading = false }
        do {
            let generated = try await RouteGenerator().bestLoop(
                start: location.coordinate,
                lengthM: lengthKm * 1000,
                profile: profile,
                round: round
            )
            result = generated
            fit(generated.best)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func fit(_ route: GeneratedRoute) {
        let line = MKPolyline(coordinates: route.coordinates, count: route.coordinates.count)
        let rect = line.boundingMapRect
        let padded = rect.insetBy(dx: -rect.width * 0.25, dy: -rect.height * 0.25)
        withAnimation { camera = .rect(padded) }
    }
}

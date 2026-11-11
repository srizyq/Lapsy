import SwiftUI
import MapKit

struct LiveRunScreen: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let session = app.session {
            RunView(session: session) {
                session.close()
                app.session = nil
                app.tab = .generator
            }
            .id(ObjectIdentifier(session))
        } else {
            PlaceholderScreen(
                tag: "Live run",
                title: "Nothing in progress",
                note: "Pick a route in Generator and tap Start."
            )
        }
    }
}

private struct RunView: View {
    let session: RunSession
    let onDone: () -> Void

    @Environment(RunStore.self) private var store
    @State private var savedId: UUID?
    @State private var tooShort = false
    @State private var discarded = false
    @State private var rating = 0
    @State private var camera: MapCameraPosition = .automatic
    @State private var confirmFinish = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                switch session.phase {
                case .ready: readyContent
                case .running, .paused: activeContent
                case .finished: summaryContent
                }
            }
            .padding(Metrics.gutter)
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .running {
                camera = .userLocation(followsHeading: false, fallback: .automatic)
            }
            if phase == .finished, savedId == nil {
                // Keep the outing straight away so it can't be lost.
                if let run = session.makeSavedRun() {
                    store.add(run)
                    savedId = run.id
                } else {
                    tooShort = true
                }
            }
        }
        .confirmationDialog("Finish this \(session.activity.noun)?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish \(session.activity.noun)") { session.finish() }
            Button("Keep going", role: .cancel) {}
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.environment["LAPSY_AUTOBEGIN"] == "1" {
                try? await Task.sleep(for: .seconds(2))
                session.begin()
            }
        }
        #endif
    }

    // MARK: - Ready

    private var readyContent: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("Ready", color: Palette.primary)
                Text(session.activity.name)
                    .font(Typeface.headline(26))
                    .foregroundStyle(Palette.textPrimary)
                Text(readyNote)
                    .font(Typeface.body(14))
                    .foregroundStyle(Palette.textSecondary)
            }
            .card()

            if session.route != nil { mapCard(height: 280) }

            if session.denied {
                Text("Location is off for Lapsy. Turn it on in Settings so the run can be tracked.")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.destructive)
                    .card()
            } else if let toStart = session.distanceToStartM, session.route != nil, toStart > 150 {
                Text("You are \(Self.distance(toStart)) from the start. Lapsy will guide you to the route once you begin.")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.textSecondary)
                    .card()
            }

            Button {
                session.begin()
            } label: {
                Text(session.current == nil && !session.denied ? "Waiting for GPS..." : "Begin")
            }
            .buttonStyle(LapsyButtonStyle(kind: .primary))
            .disabled(session.current == nil || session.denied)

            Button("Cancel", action: onDone)
                .buttonStyle(LapsyButtonStyle(kind: .outlined))
        }
    }

    private var readyNote: String {
        if let route = session.route {
            return String(format: "%.2f km route from %@.", route.distanceM / 1000, session.startName)
        }
        return "Tracking only. Lapsy records your GPS track, time and distance."
    }

    // MARK: - Active

    private var activeContent: some View {
        VStack(spacing: 12) {
            if session.route != nil { turnBanner }
            mapCard(height: 300)
            if session.route != nil { progressCard }
            metricsGrid
            controls
        }
    }

    private var turnBanner: some View {
        let nav = session.nav
        return HStack(spacing: 14) {
            Image(systemName: nav.arrived ? "flag.fill" : (nav.nextStep?.symbol ?? "arrow.up"))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.onPrimary)
                .frame(width: 56, height: 56)
                .background(Palette.primary)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))

            VStack(alignment: .leading, spacing: 4) {
                if let note = session.statusNote {
                    MonoLabel(note, color: nav.arrived ? Palette.primary : Palette.destructive)
                } else {
                    MonoLabel("Next turn", color: Palette.primary)
                }
                Text(nav.arrived ? "Arrived" : (nav.distanceToNextM.map(Self.distance) ?? "--"))
                    .font(Typeface.headline(30))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
                if !nav.arrived, let step = nav.nextStep {
                    Text(step.instruction)
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private func mapCard(height: CGFloat) -> some View {
        Map(position: $camera) {
            UserAnnotation()
            if let route = session.route {
                let split = min(session.nav.routeIndex, route.coordinates.count - 1)
                if session.phase != .ready, split > 0 {
                    MapPolyline(coordinates: Array(route.coordinates[0...split]))
                        .stroke(Palette.textMuted, lineWidth: 4)
                }
                MapPolyline(coordinates: Array(route.coordinates[(session.phase == .ready ? 0 : split)...]))
                    .stroke(Palette.primary, lineWidth: 4)
            }
            if session.breadcrumb.count > 1 {
                MapPolyline(coordinates: session.breadcrumb)
                    .stroke(Palette.tertiary.opacity(0.8), lineWidth: 2)
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
        )
    }

    private var progressCard: some View {
        let total = max(1, session.routeTotalM)
        let done = min(total, session.nav.distanceAlongM)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel("Route progress")
                Spacer()
                Text(String(format: "%.2f", done / 1000))
                    .font(Typeface.headline(24))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
                Text(String(format: "/ %.2f KM", total / 1000))
                    .font(Typeface.label(11))
                    .foregroundStyle(Palette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.well)
                    Rectangle().fill(Palette.primary).frame(width: geo.size.width * done / total)
                }
            }
            .frame(height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .card()
    }

    private var metricsGrid: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wheels = session.activity.group == .wheels
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    metric(wheels ? "Speed" : "Pace", wheels ? Self.speed(session.speedKmh) : Self.pace(session.paceSecPerKm),
                           unit: wheels ? "km/h" : "/km")
                    metric("Time", Self.clock(session.elapsed(at: context.date)), unit: "")
                    metric("Heart", HealthService.shared.heartRate.map(String.init) ?? "--", unit: "bpm")
                }
                HStack(spacing: 8) {
                    metric("Distance", String(format: "%.2f", session.distanceM / 1000), unit: "km")
                    metric("Energy", String(format: "%.0f", session.energyKcal), unit: "kcal")
                    metric("Remaining",
                           session.route == nil ? "--" : String(format: "%.2f", session.nav.remainingM / 1000),
                           unit: "km")
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(label, size: 9)
            Text(value)
                .font(Typeface.headline(22))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit.uppercased())
                .font(Typeface.label(9))
                .foregroundStyle(Palette.textSecondary)
                .frame(height: 11, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
        )
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if session.phase == .running {
                Button("Pause") { session.pause() }
                    .buttonStyle(LapsyButtonStyle(kind: .secondary))
            } else {
                Button("Resume") { session.resume() }
                    .buttonStyle(LapsyButtonStyle(kind: .primary))
            }
            Button("Finish") { confirmFinish = true }
                .buttonStyle(LapsyButtonStyle(kind: .outlined))
        }
    }

    // MARK: - Summary

    private var summaryContent: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("\(session.activity.noun) complete", color: Palette.primary)
                Text(session.activity.name)
                    .font(Typeface.headline(26))
                    .foregroundStyle(Palette.textPrimary)
                if session.rerouteCount > 0 {
                    Text("Rerouted \(session.rerouteCount) time\(session.rerouteCount == 1 ? "" : "s").")
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .card()

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    metric("Distance", String(format: "%.2f", session.distanceM / 1000), unit: "km")
                    metric("Time", Self.clock(session.elapsed()), unit: "")
                }
                HStack(spacing: 8) {
                    metric("Avg pace", Self.pace(session.averagePaceSecPerKm), unit: "/km")
                    metric("Energy", String(format: "%.0f", session.energyKcal), unit: "kcal")
                }
                if let hr = HealthService.shared.averageHeartRate {
                    HStack(spacing: 8) {
                        metric("Avg heart", "\(hr)", unit: "bpm")
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }

            if savedId != nil {
                Text("Saved to your Activity.")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if session.route != nil { ratingCard }
            } else if tooShort {
                Text("That was under 50 m, so it wasn't saved.")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if discarded {
                Text("Discarded. Nothing was saved.")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Done", action: onDone)
                .buttonStyle(LapsyButtonStyle(kind: .primary))

            if let id = savedId, let run = store.runs.first(where: { $0.id == id }) {
                Button("Discard this \(session.activity.noun)") {
                    store.delete(run)
                    savedId = nil
                    discarded = true
                }
                .font(Typeface.label(11))
                .foregroundStyle(Palette.destructive)
                .padding(.top, 4)
            }
        }
    }

    private var ratingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("How was this route?")
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = star
                        if let id = savedId { store.setRating(star, for: id) }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 24))
                            .foregroundStyle(star <= rating ? Palette.primary : Palette.textMuted)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                }
                Spacer()
            }
        }
        .card()
    }

    // MARK: - Formatting

    static func distance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int((meters / 10).rounded()) * 10) m" : String(format: "%.1f km", meters / 1000)
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func pace(_ secPerKm: Double?) -> String {
        guard let sec = secPerKm, sec < 3600 else { return "--:--" }
        return String(format: "%d:%02d", Int(sec) / 60, Int(sec) % 60)
    }

    static func speed(_ kmh: Double?) -> String {
        kmh.map { String(format: "%.1f", $0) } ?? "--"
    }
}

extension RouteStep {
    /// SF Symbol for the maneuver.
    var symbol: String {
        switch type {
        case 0, 2: "arrow.turn.up.left"
        case 1, 3: "arrow.turn.up.right"
        case 4, 12: "arrow.up.left"
        case 5, 13: "arrow.up.right"
        case 7, 8: "arrow.triangle.2.circlepath"
        case 9: "arrow.uturn.down"
        case 10: "flag.fill"
        default: "arrow.up"
        }
    }
}

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
    /// Map follows you, turned to face the way you travel. Off shows the whole route.
    @State private var following = true
    @State private var heading: Double = 0

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
                following = true
                updateCamera()
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
        .onChange(of: session.current) { _, _ in
            if session.phase == .running || session.phase == .paused, following { updateCamera() }
        }
        .onChange(of: following) { _, _ in updateCamera() }
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
            mapCard(height: 360)
                .overlay(alignment: .topLeading) { mapOverlayTop }
                .overlay(alignment: .topTrailing) { mapButtons }
                .overlay(alignment: .bottomLeading) { mapOverlayBottom }
            distanceHero
            liveTiles
            controls
        }
    }

    private var turnBanner: some View {
        let nav = session.nav
        let offRoute = session.statusNote != nil && !nav.arrived
        let steps = session.route?.steps ?? []
        let then: RouteStep? = {
            guard let i = nav.nextStepIndex, steps.indices.contains(i + 1) else { return nil }
            let next = steps[i + 1]
            return next.type == 10 ? nil : next
        }()
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: nav.arrived ? "flag.fill" : (nav.nextStep?.symbol ?? "arrow.up"))
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Palette.onPrimary)
                    .frame(width: 68, height: 68)
                    .background(offRoute ? Palette.destructive : Palette.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))

                VStack(alignment: .leading, spacing: 3) {
                    if let note = session.statusNote {
                        MonoLabel(note, color: nav.arrived ? Palette.primary : Palette.destructive)
                    } else {
                        MonoLabel("Next turn", color: Palette.primary)
                    }
                    Text(nav.arrived ? "Arrived" : (nav.distanceToNextM.map(Self.distance) ?? "--"))
                        .font(Typeface.headline(38))
                        .foregroundStyle(Palette.textPrimary)
                        .monospacedDigit()
                    if !nav.arrived, let step = nav.nextStep {
                        Text(step.instruction)
                            .font(Typeface.body(14))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Metrics.cardPadding)

            if let then, !nav.arrived {
                Rectangle().fill(Palette.hairline).frame(height: Metrics.hairline)
                HStack(spacing: 10) {
                    MonoLabel("Then", size: 9)
                    Image(systemName: then.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.primary)
                    Text(then.instruction)
                        .font(Typeface.body(12))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let toNext = nav.distanceToNextM, let i = nav.nextStepIndex {
                        Text(Self.distance(toNext + steps[i].distanceM))
                            .font(Typeface.label(11, weight: .bold))
                            .foregroundStyle(Palette.textPrimary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.vertical, 10)
                .background(Palette.well)
            }
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(offRoute ? Palette.destructive : Palette.hairline, lineWidth: offRoute ? 1.5 : Metrics.hairline)
        )
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
        .mapStyle(.standard(
            elevation: session.phase != .ready && following ? .realistic : .flat,
            pointsOfInterest: session.phase != .ready && following ? .excludingAll : .all
        ))
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
        )
    }

    private var mapButtons: some View {
        VStack(spacing: 8) {
            mapButton(following ? "map" : "location.north.line.fill", label: following ? "Show whole route" : "Follow me") {
                following.toggle()
            }
            mapButton(session.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                      label: session.voiceOn ? "Turn voice off" : "Turn voice on") {
                session.voiceOn.toggle()
            }
        }
        .padding(8)
    }

    private func mapButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 38, height: 38)
                .background(Palette.neutral.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
                    .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
        }
        .accessibilityLabel(label)
    }

    /// Chase view: close in, tilted, facing the way you are moving, with you low on screen.
    private func updateCamera() {
        guard following else {
            if let route = session.route {
                let rect = MKPolyline(coordinates: route.coordinates, count: route.coordinates.count).boundingMapRect
                withAnimation { camera = .rect(rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2)) }
            } else {
                camera = .userLocation(fallback: .automatic)
            }
            return
        }
        guard let here = session.current else {
            camera = .userLocation(followsHeading: true, fallback: .automatic)
            return
        }
        if here.course >= 0, here.speed >= 0.8 { heading = here.course }
        let ahead = 70.0
        let rad = heading * .pi / 180
        let centre = CLLocationCoordinate2D(
            latitude: here.coordinate.latitude + ahead * cos(rad) / 111_000,
            longitude: here.coordinate.longitude + ahead * sin(rad) / (111_000 * cos(here.coordinate.latitude * .pi / 180))
        )
        withAnimation(.easeOut(duration: 0.8)) {
            camera = .camera(MapCamera(centerCoordinate: centre, distance: 450, heading: heading, pitch: 60))
        }
    }

    // Chips on top of the map. They only appear when there is something real to show.
    private var mapOverlayTop: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            if let song = session.nowPlaying() {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.primary)
                    VStack(alignment: .leading, spacing: 1) {
                        MonoLabel("Now playing", size: 8)
                        Text(song.artist.isEmpty ? song.title : "\(song.title) · \(song.artist)")
                            .font(Typeface.body(12, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.neutral.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
                    .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                .padding(8)
                .frame(maxWidth: 260, alignment: .leading)
            }
        }
    }

    private var mapOverlayBottom: some View {
        HStack(spacing: 6) {
            if let climb = session.climbAhead(400) {
                mapChip("Climb in 400 m", String(format: "%+.0f m", climb))
            }
            if let grade = session.gradePercent {
                mapChip("Slope", String(format: "%+.1f%%", grade))
            }
        }
        .padding(8)
    }

    private func mapChip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            MonoLabel(label, size: 8)
            Text(value)
                .font(Typeface.headline(15))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.neutral.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
            .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
    }

    private var distanceHero: some View {
        let total = session.routeTotalM
        let done = session.route == nil ? 0 : min(total, session.nav.distanceAlongM)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text(String(format: "%.2f", session.distanceM / 1000))
                    .font(Typeface.headline(44))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
                Text("KM")
                    .font(Typeface.label(12))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                if session.route != nil, total > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        MonoLabel("Route progress", size: 9)
                        Text(String(format: "of %.2f km (%d%%)", total / 1000, Int((done / total * 100).rounded())))
                            .font(Typeface.label(11))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            if session.route != nil, total > 0 { ProgressLine(fraction: done / total, height: 6) }
        }
        .card()
    }

    private var liveTiles: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wheels = session.activity.group == .wheels
            let elapsed = session.elapsed(at: context.date)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    tile(wheels ? "Current speed" : "Current pace",
                         wheels ? Self.speed(session.speedKmh) : Self.pace(session.paceSecPerKm),
                         unit: wheels ? "km/h" : "/km", note: paceNote)
                    tile("Elapsed time", Self.clock(elapsed), unit: "time",
                         note: "Splits: \(session.splits.count)")
                    tile("Heart rate", HealthService.shared.heartRate.map(String.init) ?? "--", unit: "bpm",
                         note: HealthService.shared.averageHeartRate.map { "Avg \($0)" } ?? "")
                }
                HStack(spacing: 8) {
                    if !wheels {
                        smallTile("Steps / min", session.cadenceSPM.map(String.init) ?? "--", icon: "figure.walk")
                    }
                    smallTile("Energy", String(format: "%.0f kcal", session.energyKcal), icon: "flame")
                    smallTile("Time left", timeLeft(elapsed: elapsed), icon: "timer")
                }
            }
        }
    }

    /// How current pace compares with the average so far, e.g. "-0'12"".
    private var paceNote: String {
        guard let now = session.paceSecPerKm, let avg = session.averagePaceSecPerKm else { return "" }
        let d = Int((now - avg).rounded())
        return String(format: "%@%d'%02d\" vs avg", d < 0 ? "-" : "+", abs(d) / 60, abs(d) % 60)
    }

    private func timeLeft(elapsed: TimeInterval) -> String {
        guard session.route != nil, let pace = session.averagePaceSecPerKm ?? session.paceSecPerKm else { return "--" }
        return Self.clock(session.nav.remainingM / 1000 * pace)
    }

    private func tile(_ label: String, _ value: String, unit: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(label, size: 8)
            Text(value)
                .font(Typeface.headline(26))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit.uppercased())
                .font(Typeface.label(9))
                .foregroundStyle(Palette.textSecondary)
            Text(note.uppercased())
                .font(Typeface.label(8))
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 10, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
            .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
    }

    private func smallTile(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(Typeface.headline(15))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                MonoLabel(label, size: 8)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
            .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
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
        VStack(spacing: 8) {
            if session.phase == .running {
                SlideToConfirm(title: "Slide to pause") { session.pause() }
            } else {
                Button("Resume") { session.resume() }
                    .buttonStyle(LapsyButtonStyle(kind: .primary))
            }
            Button("Finish \(session.activity.noun)") { confirmFinish = true }
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
                HStack(spacing: 8) {
                    metric("Climb", String(format: "+%.0f", session.ascentM), unit: "m")
                    metric("Splits", "\(session.splits.count)", unit: "km done")
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

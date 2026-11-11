import SwiftUI
import Charts
import CoreLocation

struct ActivityScreen: View {
    @Environment(RunStore.self) private var store
    @Environment(AppState.self) private var app
    @State private var selected: SavedRun?
    @State private var splitsFor: SavedRun?
    @State private var period: StatsPeriod = .week
    @State private var editGoal = false
    @State private var goalText = ""

    var body: some View {
        let stats = PeriodStats.make(store.runs, period: period)
        let records = Records(store.runs)

        ScrollView {
            VStack(spacing: 12) {
                periodTabs

                if store.runs.isEmpty {
                    emptyCard
                } else {
                    tiles(stats)
                    volumeCard(stats)
                    if stats.newGroundShare != nil || stats.terrain != nil { discoveryCard(stats) }
                    historyHeader
                    ForEach(store.runs) { run in
                        historyCard(run, records: records)
                    }
                }

                if let error = store.lastSyncError {
                    Text("Backup paused: \(error)")
                        .font(Typeface.body(12))
                        .foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Metrics.gutter)
        }
        .sheet(item: $selected) { run in RunDetailScreen(run: run) }
        .sheet(item: $splitsFor) { run in
            SplitsSheet(run: run).presentationDetents([.medium, .large])
        }
        .alert("Weekly distance goal", isPresented: $editGoal) {
            TextField("km", text: $goalText).keyboardType(.decimalPad)
            Button("Save") { StatsPeriod.weeklyGoalKm = Double(goalText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("How many kilometres do you want to cover each week? Leave it empty or 0 to remove the goal.")
        }
    }

    // MARK: - Pieces

    private var periodTabs: some View {
        HStack(spacing: 0) {
            ForEach(StatsPeriod.allCases) { p in
                Button { withAnimation(.easeOut(duration: 0.15)) { period = p } } label: {
                    Text(p.title.uppercased())
                        .font(Typeface.label(10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(period == p ? Palette.onPrimary : Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(period == p ? Palette.primary : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
            .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("History", color: Palette.primary)
            Text("No outings yet")
                .font(Typeface.headline(22))
                .foregroundStyle(Palette.textPrimary)
            Text("Generate a route, tap Start, and your first outing will show up here.")
                .font(Typeface.body(14))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func tiles(_ s: PeriodStats) -> some View {
        let wheels = s.runs.first?.activity.group == .wheels
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Distance, with the weekly goal underneath when one is set.
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        MonoLabel("Distance", size: 9)
                        Spacer()
                        if let change = s.distanceChange { changeBadge(change) }
                    }
                    valueLine(String(format: "%.1f", s.distanceM / 1000), "km")
                    if period == .week {
                        let goal = StatsPeriod.weeklyGoalKm
                        if goal > 0 {
                            ProgressLine(fraction: s.distanceM / 1000 / goal)
                            Button { goalText = String(format: "%g", goal); editGoal = true } label: {
                                MonoLabel(String(format: "Goal: %.1f km", goal), size: 8)
                            }
                        } else {
                            Button { goalText = ""; editGoal = true } label: {
                                MonoLabel("Set a weekly goal", color: Palette.primary, size: 8)
                            }
                        }
                    }
                }
                .tileFrame()

                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel("Duration", size: 9)
                    Text(Self.hoursMinutes(s.durationS))
                        .font(Typeface.headline(26))
                        .foregroundStyle(Palette.textPrimary)
                        .monospacedDigit()
                    MonoLabel("\(s.runs.count) session\(s.runs.count == 1 ? "" : "s") completed", size: 8)
                }
                .tileFrame()
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel(wheels ? "Avg speed" : "Avg pace", size: 9)
                    valueLine(
                        wheels ? (s.avgPaceSecPerKm.map { String(format: "%.1f", 3600 / $0) } ?? "--")
                               : Fmt.pace(s.avgPaceSecPerKm),
                        wheels ? "km/h" : "/km"
                    )
                    if let d = s.paceChangeSec, !wheels {
                        let secs = Int(abs(d).rounded())
                        MonoLabel("\(d <= 0 ? "-" : "+")\(secs)s vs \(period.comparison)", size: 8)
                    } else {
                        MonoLabel(" ", size: 8)
                    }
                }
                .tileFrame()

                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel("Ascent", size: 9)
                    valueLine(s.runs.contains { $0.ascentM != nil } ? String(format: "%.0f", s.ascentM) : "--", "m")
                    MonoLabel(s.maxAscentM > 0 ? String(format: "Best outing %.0f m", s.maxAscentM) : " ", size: 8)
                }
                .tileFrame()
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func valueLine(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(value)
                .font(Typeface.headline(26))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
            Text(unit.uppercased())
                .font(Typeface.label(10))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func changeBadge(_ change: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
            Text(String(format: "%+.0f%%", change * 100))
        }
        .font(Typeface.label(9, weight: .bold))
        .foregroundStyle(Palette.textPrimary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Palette.well)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func volumeCard(_ s: PeriodStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Volume")
                    .font(Typeface.headline(18))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                if s.bestBucket != nil {
                    HStack(spacing: 5) {
                        Circle().fill(Palette.textPrimary).frame(width: 6, height: 6)
                        MonoLabel("Peak", size: 9)
                    }
                }
            }
            Chart(s.buckets) { b in
                BarMark(x: .value("When", String(b.id)), y: .value("km", b.km), width: .ratio(0.6))
                    .foregroundStyle(b.id == s.bestBucket ? Palette.textPrimary : (b.km > 0 ? Palette.primary.opacity(0.55) : Palette.hairline))
                    .cornerRadius(2)
                    .annotation(position: .top, spacing: 3) {
                        if b.km > 0 {
                            Text(String(format: "%.1f", b.km))
                                .font(Typeface.label(9))
                                .foregroundStyle(b.id == s.bestBucket ? Palette.textPrimary : Palette.textMuted)
                        }
                    }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: s.buckets.map { String($0.id) }) { value in
                    AxisValueLabel {
                        if let key = value.as(String.self), let i = Int(key), s.buckets.indices.contains(i) {
                            Text(s.buckets[i].label.uppercased())
                                .font(Typeface.label(9))
                                .foregroundStyle(Palette.textMuted)
                        }
                    }
                }
            }
            .frame(height: 130)
        }
        .card()
    }

    private func discoveryCard(_ s: PeriodStats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let share = s.newGroundShare {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Exploring")
                            .font(Typeface.headline(18))
                            .foregroundStyle(Palette.textPrimary)
                        Spacer()
                        Text("\(Int((share * 100).rounded()))%")
                            .font(Typeface.headline(24))
                            .foregroundStyle(Palette.textPrimary)
                            .monospacedDigit()
                    }
                    ProgressLine(fraction: share, height: 5)
                    MonoLabel("of the ground you covered was new to you", size: 9)
                }
            }
            if let t = s.terrain {
                VStack(alignment: .leading, spacing: 8) {
                    if s.newGroundShare != nil { Divider().overlay(Palette.hairline) }
                    HStack {
                        Text("Terrain")
                            .font(Typeface.headline(18))
                            .foregroundStyle(Palette.textPrimary)
                        Spacer()
                        MonoLabel("From the routes you followed", size: 8)
                    }
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            Rectangle().fill(Palette.tertiary).frame(width: max(0, (geo.size.width - 4) * t.paved))
                            Rectangle().fill(Palette.secondary).frame(width: max(0, (geo.size.width - 4) * t.unpaved))
                            Rectangle().fill(Palette.hairline).frame(width: max(0, (geo.size.width - 4) * t.unknown))
                        }
                    }
                    .frame(height: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    HStack(spacing: 14) {
                        legend(Palette.tertiary, "Paved", t.paved)
                        legend(Palette.secondary, "Path / dirt", t.unpaved)
                        if t.unknown > 0.05 { legend(Palette.hairline, "Unknown", t.unknown) }
                    }
                }
            }
        }
        .card()
    }

    private func legend(_ color: Color, _ title: String, _ share: Double) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            Text("\(title) \(Int((share * 100).rounded()))%")
                .font(Typeface.label(9))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    // MARK: - History

    private var historyHeader: some View {
        HStack {
            Text("History")
                .font(Typeface.headline(18))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            MonoLabel("\(store.runs.count) logged", size: 9)
        }
        .padding(.top, 6)
    }

    private func historyCard(_ run: SavedRun, records: Records) -> some View {
        let badges = records.badges(for: run)
        let wheels = run.activity.group == .wheels
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Tag(text: Self.relativeDay(run.startedAt), highlighted: false)
                        MonoLabel(run.startedAt.formatted(.dateTime.hour().minute()), size: 9)
                    }
                    Text("\(run.activity.name)\(run.startName.isEmpty ? "" : " · \(run.startName)")")
                        .font(Typeface.headline(17))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                }
                Spacer()
                Menu {
                    Button("Open details") { selected = run }
                    Button("Delete", role: .destructive) { store.delete(run) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Palette.well)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                }
            }

            HStack(spacing: 12) {
                RouteShape(coordinates: run.trackCoordinates)
                    .frame(width: 96, height: 96)
                    .background(Palette.well)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                    .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
                        .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        stat("Distance", Fmt.km(run.distanceM), "km", big: true)
                        stat("Time", Fmt.clock(run.durationS), "", big: true)
                    }
                    GridRow {
                        stat(wheels ? "Speed" : "Pace",
                             wheels ? (run.averageSpeedKmh.map { String(format: "%.1f", $0) } ?? "--") : Fmt.pace(run.averagePaceSecPerKm),
                             wheels ? "km/h" : "/km")
                        stat("Climb", run.ascentM.map { String(format: "+%.0f", $0) } ?? "--", "m")
                    }
                }
            }

            if !badges.isEmpty || run.avgHeartRate != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(badges, id: \.self) { Tag(text: $0, icon: "trophy", highlighted: true) }
                        if let hr = run.avgHeartRate { Tag(text: "Avg \(hr) bpm", icon: "heart") }
                    }
                }
            }

            HStack(spacing: 8) {
                Button { regenerate(run) } label: {
                    Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                        .font(Typeface.label(10, weight: .bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Palette.well)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                        .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
                            .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                }
                .disabled(!run.activity.canRoute)
                .opacity(run.activity.canRoute ? 1 : 0.4)

                Button { splitsFor = run } label: {
                    Label("Splits", systemImage: "chart.bar.xaxis")
                        .font(Typeface.label(10, weight: .bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Palette.well)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                        .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
                            .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                }
                .disabled((run.splits ?? []).isEmpty)
                .opacity((run.splits ?? []).isEmpty ? 0.4 : 1)
            }
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture { selected = run }
    }

    private func stat(_ label: String, _ value: String, _ unit: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            MonoLabel(label, size: 8)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(Typeface.headline(big ? 22 : 15))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Typeface.label(9))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    /// Opens the Generator ready to make a fresh route of the same kind and length from the same start.
    private func regenerate(_ run: SavedRun) {
        let g = app.generator
        g.setActivity(run.activity)
        g.lengthKm = min(max((run.plannedDistanceM ?? run.distanceM) / 1000, g.lengthRange.lowerBound), g.lengthRange.upperBound)
        if let first = run.trackCoordinates.first {
            g.start = StartPoint(name: run.startName.isEmpty ? "Past start" : run.startName, coordinate: first)
            g.usingCurrentLocation = false
        }
        g.reset()
        g.autoGenerate = true
        app.tab = .generator
    }

    // MARK: - Formatting

    static func hoursMinutes(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        return m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))m" : "\(m)m"
    }

    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 0
        if days < 7 { return "\(days) days ago" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

private extension View {
    func tileFrame() -> some View {
        self.padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
    }
}

/// Time for each kilometre of an outing.
struct SplitsSheet: View {
    let run: SavedRun
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let splits = run.splits ?? []
        let fastest = splits.min()
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        MonoLabel("Splits", color: Palette.primary)
                        Text("\(run.activity.name) · \(Fmt.km(run.distanceM)) km")
                            .font(Typeface.headline(20))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(Typeface.label(11))
                        .foregroundStyle(Palette.textSecondary)
                }
                ForEach(Array(splits.enumerated()), id: \.offset) { i, seconds in
                    HStack {
                        Text("KM \(i + 1)")
                            .font(Typeface.label(11))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 52, alignment: .leading)
                        GeometryReader { geo in
                            let longest = splits.max() ?? 1
                            Rectangle()
                                .fill(seconds == fastest ? Palette.textPrimary : Palette.primary.opacity(0.6))
                                .frame(width: geo.size.width * seconds / longest)
                        }
                        .frame(height: 8)
                        Text(Fmt.clock(seconds))
                            .font(Typeface.label(12, weight: .bold))
                            .foregroundStyle(Palette.textPrimary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                if splits.isEmpty {
                    Text("Splits appear for outings of 1 km or more.")
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.neutral.ignoresSafeArea())
    }
}

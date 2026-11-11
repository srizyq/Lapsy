import SwiftUI
import Charts

struct ActivityScreen: View {
    @Environment(RunStore.self) private var store
    @State private var selected: SavedRun?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                weekCard

                if store.runs.isEmpty {
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
                } else {
                    HStack {
                        MonoLabel("History")
                        Spacer()
                        MonoLabel("\(store.runs.count) total", size: 10)
                    }
                    .padding(.top, 4)
                    ForEach(store.runs) { run in
                        Button { selected = run } label: { row(run) }
                            .buttonStyle(.plain)
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
        .sheet(item: $selected) { run in
            RunDetailScreen(run: run)
        }
    }

    // MARK: - This week

    private struct Day: Identifiable {
        let id: Date
        let km: Double
    }

    private var lastSevenDays: [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let meters = store.runs
                .filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
                .reduce(0) { $0 + $1.distanceM }
            return Day(id: day, km: meters / 1000)
        }
    }

    private var weekCard: some View {
        let days = lastSevenDays
        let weekRuns = store.runs.filter {
            $0.startedAt >= Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        }
        let km = days.reduce(0) { $0 + $1.km }
        let time = weekRuns.reduce(0) { $0 + $1.durationS }

        return VStack(alignment: .leading, spacing: 12) {
            MonoLabel("Last 7 days", color: Palette.primary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", km))
                    .font(Typeface.headline(38))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
                Text("KM")
                    .font(Typeface.label(11))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(weekRuns.count) outing\(weekRuns.count == 1 ? "" : "s")")
                    Text(Fmt.clock(time))
                }
                .font(Typeface.label(11))
                .foregroundStyle(Palette.textSecondary)
            }

            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.id, unit: .day),
                    y: .value("km", day.km)
                )
                .foregroundStyle(day.km > 0 ? Palette.primary : Palette.hairline)
                .cornerRadius(2)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        .font(Typeface.label(9))
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .frame(height: 90)
        }
        .card()
    }

    // MARK: - Row

    private func row(_ run: SavedRun) -> some View {
        HStack(spacing: 12) {
            Image(systemName: run.activity.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.primary)
                .frame(width: 40, height: 40)
                .background(Palette.well)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))

            VStack(alignment: .leading, spacing: 3) {
                Text(run.activity.name)
                    .font(Typeface.body(15, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Text(Fmt.when(run.startedAt))
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Fmt.km(run.distanceM)) km")
                    .font(Typeface.headline(17))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
                Text(Fmt.clock(run.durationS))
                    .font(Typeface.label(11))
                    .foregroundStyle(Palette.textSecondary)
            }
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

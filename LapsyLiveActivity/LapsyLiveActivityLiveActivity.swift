import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private enum Tint {
    static let bg = Color(red: 0.07, green: 0.075, blue: 0.09)
    static let panel = Color(red: 0.12, green: 0.125, blue: 0.145)
    static let primary = Color(red: 0.831, green: 0.725, blue: 0.588)
    static let text = Color(red: 0.93, green: 0.92, blue: 0.9)
    static let muted = Color(red: 0.62, green: 0.62, blue: 0.64)
    static let coral = Color(red: 0.93, green: 0.42, blue: 0.38)
}

private func distanceText(_ m: Double?) -> String {
    guard let m else { return "" }
    if m < 1000 { return "\(Int((m / 10).rounded()) * 10) m" }
    return String(format: "%.1f km", m / 1000)
}

private func totalText(_ m: Double) -> String { String(format: "%.2f km", m / 1000) }

private struct Clock: View {
    let state: LapsyRunAttributes.ContentState
    var body: some View {
        if let start = state.clockStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        } else {
            Text(format(state.elapsedS)).monospacedDigit()
        }
    }
    private func format(_ s: Double) -> String {
        let t = Int(s)
        return t >= 3600
            ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60)
            : String(format: "%d:%02d", t / 60, t % 60)
    }
}

private struct ArrowTile: View {
    let state: LapsyRunAttributes.ContentState
    var size: CGFloat = 48
    var body: some View {
        Image(systemName: state.arrow)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(state.offRoute ? Tint.coral : Tint.bg)
            .frame(width: size, height: size)
            .background(state.offRoute ? Tint.coral.opacity(0.18) : Tint.primary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct Stat: View {
    let label: String
    let value: AnyView
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(Tint.muted)
            value.font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(Tint.text)
        }
    }
}

private struct Stats: View {
    let state: LapsyRunAttributes.ContentState
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Stat(label: "DISTANCE", value: AnyView(Text(totalText(state.distanceM))))
            Stat(label: "TIME", value: AnyView(Clock(state: state)))
            Stat(label: "PACE", value: AnyView(Text(state.paceText)))
            if let hr = state.heartRate {
                Stat(label: "HEART", value: AnyView(Text("\(hr)")))
            }
            Spacer(minLength: 0)
        }
    }
}

private struct Buttons: View {
    let state: LapsyRunAttributes.ContentState
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: PauseRunIntent()) {
                Label(state.paused ? "Resume" : "Pause", systemImage: state.paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .foregroundStyle(Tint.bg)
                    .background(Tint.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            Button(intent: FinishRunIntent()) {
                Label("Finish", systemImage: "flag.checkered")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .foregroundStyle(Tint.coral)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Tint.coral, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct LockScreenView: View {
    let state: LapsyRunAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ArrowTile(state: state, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    if !state.paused, state.turnDistanceM != nil {
                        Text(distanceText(state.turnDistanceM))
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .foregroundStyle(state.offRoute ? Tint.coral : Tint.text)
                    }
                    Text(state.paused ? "Paused" : state.instruction)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(state.paused ? Tint.primary : Tint.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            Stats(state: state)
            Buttons(state: state)
        }
        .padding(14)
    }
}

struct LapsyRunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LapsyRunAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Tint.bg)
                .activitySystemActionForegroundColor(Tint.primary)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ArrowTile(state: s, size: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(distanceText(s.turnDistanceM))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(s.offRoute ? Tint.coral : Tint.text)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(s.paused ? "Paused" : s.instruction)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .foregroundStyle(Tint.text)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        Stats(state: s)
                        Buttons(state: s)
                    }
                }
            } compactLeading: {
                Image(systemName: s.arrow)
                    .foregroundStyle(s.offRoute ? Tint.coral : Tint.primary)
            } compactTrailing: {
                if s.paused {
                    Image(systemName: "pause.fill").foregroundStyle(Tint.primary)
                } else {
                    Text(distanceText(s.turnDistanceM))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Tint.text)
                }
            } minimal: {
                Image(systemName: s.arrow).foregroundStyle(Tint.primary)
            }
            .keylineTint(Tint.primary)
        }
    }
}

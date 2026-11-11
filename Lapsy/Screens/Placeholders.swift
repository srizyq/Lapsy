import SwiftUI

/// Shell screens. Each one is replaced by the real screen in its build step.
struct PlaceholderScreen: View {
    let tag: String
    let title: String
    let note: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    MonoLabel(tag, color: Palette.primary)
                    Text(title)
                        .font(Typeface.headline(26))
                        .foregroundStyle(Palette.textPrimary)
                    Text(note)
                        .font(Typeface.body(14))
                        .foregroundStyle(Palette.textSecondary)
                }
                .card()
            }
            .padding(Metrics.gutter)
        }
    }
}

struct LiveRunScreen: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let planned = app.planned {
            PlaceholderScreen(
                tag: "Live run",
                title: planned.activity.name,
                note: planned.route.map {
                    String(format: "%.2f km route from %@. Live navigation comes next.", $0.distanceM / 1000, planned.startName)
                } ?? "Tracking only from \(planned.startName). Live tracking comes next."
            )
        } else {
            PlaceholderScreen(
                tag: "Live run",
                title: "No run in progress",
                note: "Start a route from Generator to see live navigation."
            )
        }
    }
}

struct ActivityScreen: View {
    var body: some View {
        PlaceholderScreen(
            tag: "Activity",
            title: "Your history",
            note: "Weekly stats and logged runs go here."
        )
    }
}

struct SavedScreen: View {
    var body: some View {
        PlaceholderScreen(
            tag: "Saved",
            title: "Saved routes",
            note: "Routes you keep, with search and filters."
        )
    }
}

struct ProfileScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("Profile", color: Palette.primary)
                Text("Your profile")
                    .font(Typeface.headline(26))
                    .foregroundStyle(Palette.textPrimary)
                Text("Name, avatar, streak, stats and settings go here.")
                    .font(Typeface.body(14))
                    .foregroundStyle(Palette.textSecondary)
            }
            .card()

            Button("Close") { dismiss() }
                .buttonStyle(LapsyButtonStyle(kind: .outlined))

            Spacer()
        }
        .padding(Metrics.gutter)
        .background(Palette.neutral.ignoresSafeArea())
    }
}

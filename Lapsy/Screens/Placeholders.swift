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

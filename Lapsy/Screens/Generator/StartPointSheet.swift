import SwiftUI
import MapKit

/// Pick where a route starts: current location or a searched place.
struct StartPointSheet: View {
    @Environment(\.dismiss) private var dismiss
    var location: LocationProvider
    var title = "Start point"
    /// The current-location shortcut only makes sense for a start point.
    var showCurrent = true
    /// Called with the chosen point and whether it is the live current location.
    var onPick: (StartPoint, Bool) -> Void

    @State private var query = ""
    @State private var results: [StartPoint] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MonoLabel(title, color: Palette.primary)
                Spacer()
                Button("Close") { dismiss() }
                    .font(Typeface.label(11, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.textMuted)
                TextField("Search a place", text: $query)
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.textPrimary)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
            }
            .padding(12)
            .background(Palette.well)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.corner)
                    .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
            )

            if showCurrent { Button {
                if let c = location.coordinate {
                    onPick(StartPoint(name: "Current location", coordinate: c), true)
                    dismiss()
                } else {
                    location.request()
                }
            } label: {
                HStack {
                    Image(systemName: "location.fill")
                    Text(location.denied
                         ? "Location is off. Enable it in Settings"
                         : (location.coordinate == nil ? "Finding your location..." : "Use current location"))
                }
            }
            .buttonStyle(LapsyButtonStyle(kind: .outlined)) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, place in
                        Button {
                            onPick(place, false)
                            dismiss()
                        } label: {
                            HStack {
                                Text(place.name)
                                    .font(Typeface.body(15))
                                    .foregroundStyle(Palette.textPrimary)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(Palette.hairline).frame(height: Metrics.hairline)
                    }
                }
            }
        }
        .padding(Metrics.gutter)
        .background(Palette.neutral.ignoresSafeArea())
        .presentationDetents([.large])
        .task(id: query) { await search() }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        guard let response = try? await MKLocalSearch(request: request).start() else { return }
        results = response.mapItems.prefix(8).map {
            StartPoint(name: $0.name ?? "Place", coordinate: $0.placemark.coordinate)
        }
    }
}

import SwiftUI
import UIKit

private struct SharedRouteRow: Encodable {
    var id: UUID
    var name: String
    var activityId: String
    var distanceM: Double
    var ascentM: Double
    var polyline: String
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// A "Share" button. Tapping it asks first (the link is public), uploads the route,
/// then opens the iOS share sheet with a link to the web page.
struct ShareRouteButton: View {
    /// Keep the same id to reuse one link for a saved route; nil makes a fresh link each time.
    var id: UUID?
    let name: String
    let activityId: String
    let route: () -> StoredRoute

    @Environment(AccountStore.self) private var account
    @State private var confirm = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var item: ShareItem?

    static let base = "https://srizyq.github.io/Lapsy/r/"

    var body: some View {
        VStack(spacing: 6) {
            Button { confirm = true } label: {
                Text(busy ? "Creating link..." : "Share")
            }
            .buttonStyle(LapsyButtonStyle(kind: .outlined))
            .disabled(busy)

            if let errorText {
                Text(errorText)
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .confirmationDialog(
            "Anyone with the link can see this route and where it starts.",
            isPresented: $confirm, titleVisibility: .visible
        ) {
            Button("Create link") { Task { await create() } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $item) { item in
            ActivitySheet(items: ["Check out this route on Lapsy", item.url])
                .presentationDetents([.medium, .large])
        }
    }

    private func create() async {
        guard account.state == .signedIn, account.user != nil else {
            errorText = "Sign in to share a route."
            return
        }
        busy = true
        errorText = nil
        defer { busy = false }

        let stored = route()
        let shareId = id ?? UUID()
        let row = SharedRouteRow(
            id: shareId, name: name, activityId: activityId,
            distanceM: stored.distanceM, ascentM: stored.ascentM, polyline: stored.polyline
        )
        do {
            _ = try await account.rest(
                "rest/v1/shared_routes", method: "POST", query: ["on_conflict": "id"], body: [row],
                headers: ["Prefer": "resolution=merge-duplicates,return=minimal"]
            )
            if let url = URL(string: Self.base + "#" + shareId.uuidString.lowercased()) {
                item = ShareItem(url: url)
            }
        } catch {
            errorText = (error as? APIError)?.message ?? "Couldn't create the link. Try again."
        }
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

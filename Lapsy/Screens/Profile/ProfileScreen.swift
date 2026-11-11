import SwiftUI

struct ProfileScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var account

    @State private var draft = Profile(id: "")
    @State private var weight = ""
    @State private var height = ""
    @State private var birthYear = ""
    @State private var saving = false
    @State private var saveNote: String?
    @State private var confirmSignOut = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                statsCard
                preferencesCard
                bodyCard
                subscriptionCard
                accountCard
            }
            .padding(Metrics.gutter)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.neutral.ignoresSafeArea())
        .onAppear(perform: load)
        .onChange(of: account.profile) { _, _ in load() }
        .confirmationDialog("Sign out of Lapsy?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out") {
                Task {
                    await account.signOut()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete your account? This permanently removes your profile, runs and saved routes. It can't be undone.",
            isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { if await account.deleteAccount() { dismiss() } }
            }
            Button("Keep my account", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 14) {
            Text(initial)
                .font(Typeface.headline(26))
                .foregroundStyle(Palette.onPrimary)
                .frame(width: 64, height: 64)
                .background(Palette.primary)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(Typeface.headline(22))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if let email = account.user?.email {
                    Text(email)
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                MonoLabel("0 day streak", color: Palette.primary)
            }
            Spacer(minLength: 0)
            Button("Close") { dismiss() }
                .font(Typeface.label(11))
                .foregroundStyle(Palette.textSecondary)
        }
        .card()
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Stats")
            HStack(spacing: 8) {
                stat("Runs", "0")
                stat("Distance", "0.0 \(draft.isMetric ? "km" : "mi")")
                stat("Time", "0:00")
            }
            Text("Your totals appear here once runs are saved.")
                .font(Typeface.body(12))
                .foregroundStyle(Palette.textMuted)
        }
        .card()
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Preferences")
            HStack(spacing: 0) {
                unitButton("Metric", value: "metric")
                unitButton("Imperial", value: "imperial")
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
        }
        .card()
    }

    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Body info")
            Text("Used only to estimate calories. It stays private to your account.")
                .font(Typeface.body(12))
                .foregroundStyle(Palette.textMuted)
            TextField("", text: Binding(get: { draft.displayName ?? "" }, set: { draft.displayName = $0 }),
                      prompt: Text("Name").foregroundStyle(Palette.textMuted))
                .modifier(InputStyle())
            HStack(spacing: 8) {
                TextField("", text: $weight, prompt: Text("Weight (\(draft.isMetric ? "kg" : "lb"))").foregroundStyle(Palette.textMuted))
                    .keyboardType(.decimalPad).modifier(InputStyle())
                TextField("", text: $height, prompt: Text("Height (\(draft.isMetric ? "cm" : "in"))").foregroundStyle(Palette.textMuted))
                    .keyboardType(.decimalPad).modifier(InputStyle())
            }
            TextField("", text: $birthYear, prompt: Text("Birth year").foregroundStyle(Palette.textMuted))
                .keyboardType(.numberPad).modifier(InputStyle())

            if let saveNote {
                Text(saveNote)
                    .font(Typeface.body(13))
                    .foregroundStyle(saveNote == "Saved." ? Palette.primary : Palette.destructive)
            }
            Button(saving ? "Saving..." : "Save changes") { Task { await save() } }
                .buttonStyle(LapsyButtonStyle(kind: .primary))
                .disabled(saving || account.profile == nil)
        }
        .card()
    }

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Subscription")
            Text("Lapsy Free")
                .font(Typeface.headline(18))
                .foregroundStyle(Palette.textPrimary)
            Text("Lapsy Pro is coming. You'll be able to upgrade here.")
                .font(Typeface.body(13))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var accountCard: some View {
        VStack(spacing: 8) {
            if let error = account.errorMessage {
                Text(error)
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Sign out") { confirmSignOut = true }
                .buttonStyle(LapsyButtonStyle(kind: .outlined))
            Button("Delete account") { confirmDelete = true }
                .buttonStyle(LapsyButtonStyle(kind: .outlined))
                .foregroundStyle(Palette.destructive)
                .disabled(account.busy)
        }
    }

    // MARK: - Pieces

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(label, size: 9)
            Text(value)
                .font(Typeface.headline(18))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.well)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
    }

    private func unitButton(_ title: String, value: String) -> some View {
        let selected = draft.units == value
        return Button {
            guard draft.units != value else { return }
            convertBody(to: value)
            draft.units = value
            Task { await save(quiet: true) }
        } label: {
            Text(title.uppercased())
                .font(Typeface.label(11))
                .tracking(1)
                .foregroundStyle(selected ? Palette.onPrimary : Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(selected ? Palette.primary : Palette.well)
        }
        .buttonStyle(.plain)
    }

    private var displayName: String {
        let name = draft.displayName?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Runner" : name
    }

    private var initial: String {
        String((displayName == "Runner" ? (account.user?.email ?? "R") : displayName).prefix(1)).uppercased()
    }

    // MARK: - Data

    private func load() {
        guard let profile = account.profile else { return }
        draft = profile
        weight = profile.weightKg.map { Self.text(profile.isMetric ? $0 : $0 * 2.20462) } ?? ""
        height = profile.heightCm.map { Self.text(profile.isMetric ? $0 : $0 / 2.54) } ?? ""
        birthYear = profile.birthYear.map(String.init) ?? ""
    }

    /// Switching units converts what is typed so the stored value stays the same.
    private func convertBody(to units: String) {
        let toImperial = units == "imperial"
        if let w = Double(weight) { weight = Self.text(toImperial ? w * 2.20462 : w / 2.20462) }
        if let h = Double(height) { height = Self.text(toImperial ? h / 2.54 : h * 2.54) }
    }

    private func save(quiet: Bool = false) async {
        var edited = draft
        let metric = edited.isMetric
        edited.weightKg = Double(weight).map { metric ? $0 : $0 / 2.20462 }
        edited.heightCm = Double(height).map { metric ? $0 : $0 * 2.54 }
        edited.birthYear = Int(birthYear)
        saving = true
        defer { saving = false }
        do {
            try await account.saveProfile(edited)
            if !quiet { saveNote = "Saved." }
        } catch {
            saveNote = (error as? APIError)?.message ?? "Couldn't save. Try again."
        }
    }

    private static func text(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

private struct InputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Typeface.body(16))
            .foregroundStyle(Palette.textPrimary)
            .padding(12)
            .background(Palette.well)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
    }
}

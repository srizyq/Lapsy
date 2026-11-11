import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case generator, liveRun, activity, saved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generator: "Generator"
        case .liveRun: "Live Run"
        case .activity: "Activity"
        case .saved: "Saved"
        }
    }

    var icon: String {
        switch self {
        case .generator: "slider.horizontal.3"
        case .liveRun: "figure.run"
        case .activity: "chart.bar.xaxis"
        case .saved: "bookmark"
        }
    }
}

struct RootView: View {
    @State private var app = AppState()
    @State private var account = AccountStore()
    @State private var showProfile = false

    var body: some View {
        Group {
            switch account.state {
            case .loading:
                Palette.neutral.ignoresSafeArea()
            case .signedOut:
                SignInScreen()
            case .signedIn:
                mainContent
            }
        }
        .environment(account)
        .task { await account.restore() }
        .onChange(of: account.state) { _, state in
            if state == .signedOut {
                showProfile = false
                app.session?.close()
                app.session = nil
                app.tab = .generator
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            TopBar(onProfile: { showProfile = true })

            Group {
                switch app.tab {
                case .generator: GeneratorScreen()
                case .liveRun: LiveRunScreen()
                case .activity: ActivityScreen()
                case .saved: SavedScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(selection: Binding(get: { app.tab }, set: { app.tab = $0 }))
        }
        .background(Palette.neutral.ignoresSafeArea())
        .environment(app)
        .sheet(isPresented: $showProfile) {
            ProfileScreen()
        }
    }
}

struct TopBar: View {
    var onProfile: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("LAPSY")
                .font(Typeface.headline(20))
                .tracking(0.5)
                .foregroundStyle(Palette.textPrimary)

            Spacer()

            Button(action: onProfile) {
                Image(systemName: "person")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.onPrimary)
                    .frame(width: 32, height: 32)
                    .background(Palette.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            }
            .accessibilityLabel("Profile")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: Metrics.hairline)
        }
    }
}

struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let selected = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .medium))
                        Text(tab.title.uppercased())
                            .font(Typeface.label(9))
                            .tracking(1)
                    }
                    .foregroundStyle(selected ? Palette.primary : Palette.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(selected ? Palette.primary : .clear)
                            .frame(width: 22, height: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .background(Palette.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: Metrics.hairline)
        }
    }
}

#Preview {
    RootView()
}

import SwiftUI
import GolfKit

@main
struct FairwayApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NavigationBarStyle.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Theme.fairway)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { app.saveNow() }
        }
    }
}

enum AppTab: Hashable {
    case home, play, compete, stats, profile
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: AppTab = .home

    var body: some View {
        Group {
            if app.isOnboarded {
                TabView(selection: $tab) {
                    HomeView(selectedTab: $tab)
                        .tabItem { Label("Home", systemImage: "house.fill") }
                        .tag(AppTab.home)
                    PlayView()
                        .tabItem { Label("Play", systemImage: "figure.golf") }
                        .tag(AppTab.play)
                    CompeteView()
                        .tabItem { Label("Compete", systemImage: "trophy.fill") }
                        .tag(AppTab.compete)
                    StatsView()
                        .tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }
                        .tag(AppTab.stats)
                    ProfileView()
                        .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                        .tag(AppTab.profile)
                }
                .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: app.isOnboarded)
        .overlay(alignment: .top) { BannerOverlay() }
        .modifier(ScreenshotSupport(tab: $tab))
        .fullScreenCover(item: presentationBinding) { presentation in
            Group {
                switch presentation {
                case .round(let id): LiveRoundView(roundID: id, session: nil)
                case .match(let id): MatchFlowView(matchID: id)
                case .tournament(let id): TournamentFlowView(tournamentID: id)
                }
            }
            .environment(app)
            .overlay(alignment: .top) { BannerOverlay().environment(app) }
        }
    }

    private var presentationBinding: Binding<Presentation?> {
        Binding(get: { app.presentation }, set: { app.presentation = $0 })
    }
}

struct BannerOverlay: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let banner = app.banner {
            ToastView(title: banner.title, message: banner.message, systemImage: icon(for: banner.style), iconColor: color(for: banner.style))
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { withAnimation(.snappySpring) { app.banner = nil } }
                .id(banner.id)
        }
    }

    private func icon(for style: Banner.Style) -> String {
        switch style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .celebration: return "sparkles"
        }
    }

    private func color(for style: Banner.Style) -> Color {
        switch style {
        case .info: return Theme.OnToast.info
        case .success: return Theme.OnToast.success
        case .error: return Theme.OnToast.error
        case .celebration: return Theme.OnToast.celebration
        }
    }
}

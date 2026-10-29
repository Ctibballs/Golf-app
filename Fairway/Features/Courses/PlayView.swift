import SwiftUI
import GolfKit

/// The Play tab: find a course (search, nearby, saved) and start a round.
struct PlayView: View {
    @Environment(AppModel.self) private var app

    @State private var query = ""
    @State private var gameFilter: GameType?
    @State private var results: [CourseSummary] = []
    @State private var nearby: [CourseSummary] = []
    @State private var isSearching = false
    @State private var isLoadingNearby = false
    @State private var searchError: String?
    @State private var showCustomEditor = false
    @State private var showQuickStart = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    filterChips
                    if !query.isEmpty {
                        searchResults
                    } else {
                        quickStartCard
                        nearbySection
                        savedSection
                        demoSection
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .animation(.snappySpring, value: query.isEmpty)
            }
            .background(Theme.background)
            .navigationTitle("Play")
            .searchable(text: $query, prompt: "Search courses worldwide")
            .task(id: query) { await search() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCustomEditor = true
                    } label: {
                        Label("New course", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationDestination(for: CourseSummary.self) { CourseDetailView(summary: $0) }
            .navigationDestination(for: Round.self) { RoundDetailView(roundID: $0.id) }
            .sheet(isPresented: $showCustomEditor) { CustomCourseEditor() }
            .sheet(isPresented: $showQuickStart) { RoundSetupView() }
        }
    }

    // MARK: - Sections

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "All", isSelected: gameFilter == nil) { gameFilter = nil }
                ForEach(GameType.allCases) { type in
                    Chip(title: type.displayName, systemImage: type.symbolName, isSelected: gameFilter == type, tint: Theme.tint(for: type)) {
                        gameFilter = type
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var quickStartCard: some View {
        Button { showQuickStart = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "bolt.fill")
                    .font(.title2)
                    .frame(width: 50, height: 50)
                    .background(.white.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick start").font(.headline)
                    Text("Pick a course and tee off in seconds").font(.subheadline).opacity(0.85)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill").font(.title)
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private var searchResults: some View {
        let filtered = filter(results)
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Results", subtitle: isSearching ? "Searching…" : "\(filtered.count) courses")
            if let searchError {
                Label(searchError, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.flag)
                    .cardStyle()
            }
            if isSearching && results.isEmpty {
                ForEach(0..<3, id: \.self) { _ in LoadingCard(height: 72) }
            }
            ForEach(filtered) { summary in
                NavigationLink(value: summary) { CourseRow(summary: summary) }
                    .buttonStyle(PressableStyle())
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Text(OpenGolfAPIClient.attribution)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .animation(.snappySpring, value: results)
    }

    @ViewBuilder
    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Nearby", subtitle: "Golf, pitch & putt and mini golf around you")
            if app.location.isDenied {
                Label("Location is off. Enable it in Settings to find courses near you.", systemImage: "location.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cardStyle()
            } else if nearby.isEmpty {
                Button {
                    Task { await loadNearby() }
                } label: {
                    HStack {
                        if isLoadingNearby { ProgressView().padding(.trailing, 4) }
                        Label(isLoadingNearby ? "Looking around…" : "Find courses near me", systemImage: "location.fill")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isLoadingNearby)
            } else {
                ForEach(filter(nearby).prefix(12)) { summary in
                    NavigationLink(value: summary) { CourseRow(summary: summary) }
                        .buttonStyle(PressableStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var savedSection: some View {
        let favorites = app.library.knownCourses.filter { app.isFavorite($0.id) }
        let others = app.library.knownCourses.filter { !app.isFavorite($0.id) }
        let courses = filter((favorites + others).map(\.summary))
        if !courses.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Your courses")
                ForEach(courses) { summary in
                    NavigationLink(value: summary) { CourseRow(summary: summary, isFavorite: app.isFavorite(summary.id)) }
                        .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Demo courses", subtitle: "Fully mapped, great for trying replays and matches")
            ForEach(filter(DemoData.courses.map(\.summary))) { summary in
                NavigationLink(value: summary) { CourseRow(summary: summary) }
                    .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: - Loading

    private func filter(_ courses: [CourseSummary]) -> [CourseSummary] {
        guard let gameFilter else { return courses }
        return courses.filter { summary in
            let type = app.library.course(id: summary.id)?.gameType ?? inferredType(summary)
            return type == gameFilter
        }
    }

    private func inferredType(_ summary: CourseSummary) -> GameType {
        if summary.accessType == "miniature_golf" { return .miniGolf }
        if summary.looksLikePitchAndPutt || summary.accessType == "pitch_and_putt" { return .pitchAndPutt }
        return .golf
    }

    private func search() async {
        let text = query
        guard text.count >= 2 else {
            results = []
            searchError = nil
            return
        }
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await app.searchCourses(text)
            searchError = nil
        } catch is CancellationError {
            return
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func loadNearby() async {
        app.location.requestOneShot()
        isLoadingNearby = true
        defer { isLoadingNearby = false }
        // Give the first fix a moment to arrive.
        for _ in 0..<20 where app.location.point == nil {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard let point = app.location.point else {
            app.show(Banner(title: "No location yet", message: "Try again in a moment, or search by name.", style: .info))
            return
        }
        let found = await app.nearbyCourses(around: point)
        withAnimation(.snappySpring) { nearby = found }
        if found.isEmpty {
            app.show(Banner(title: "Nothing nearby", message: "No mapped courses within 30 km. Try searching by name.", style: .info))
        }
    }
}

struct CourseRow: View {
    @Environment(AppModel.self) private var app
    let summary: CourseSummary
    var isFavorite = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: type.symbolName)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.gradient(for: type), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(summary.name).font(.headline).lineLimit(1)
                    if isFavorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.gold) }
                }
                Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let distanceText {
                Text(distanceText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .cardStyle(padding: 12)
    }

    private var type: GameType {
        if let known = app.library.course(id: summary.id) { return known.gameType }
        if summary.accessType == "miniature_golf" { return .miniGolf }
        if summary.looksLikePitchAndPutt || summary.accessType == "pitch_and_putt" { return .pitchAndPutt }
        return .golf
    }

    private var distanceText: String? {
        guard let distance = summary.distance else { return nil }
        guard distance >= 1000 else { return app.units.distance(distance) }
        let metric = app.units.system == .metric
        let value = metric ? distance / 1000 : distance / 1609.344
        return String(format: "%.1f", value) + (metric ? " km" : " mi")
    }

    private var details: String {
        var parts: [String] = []
        if !summary.locality.isEmpty { parts.append(summary.locality) }
        if let holes = summary.holeCount { parts.append("\(holes) holes") }
        if let par = summary.par { parts.append("Par \(par)") }
        switch summary.source {
        case .openStreetMap: parts.append("OSM")
        case .custom: parts.append("Custom")
        case .demo: parts.append("Demo")
        case .openGolfAPI: break
        }
        return parts.joined(separator: " · ")
    }
}

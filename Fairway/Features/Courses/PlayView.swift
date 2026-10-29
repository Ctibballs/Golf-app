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
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 16) {
                        filterChips
                        if query.isEmpty {
                            Button { showQuickStart = true } label: {
                                HStack {
                                    Image(systemName: "bolt.fill")
                                    Text("Quick start")
                                    Spacer()
                                    Text("Pick a course and tee off").font(.subheadline).opacity(0.8)
                                }
                                .padding(.horizontal, 18)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    if !query.isEmpty {
                        searchResults
                    } else {
                        nearbySection
                        savedSection
                        demoSection
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
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
                        Label("New course", systemImage: "plus")
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
                    Chip(title: type.displayName, systemImage: type.symbolName, isSelected: gameFilter == type) {
                        gameFilter = type
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let filtered = filter(results)
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Results", subtitle: isSearching ? "Searching…" : "\(filtered.count) courses")
            if let searchError {
                Label(searchError, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.flag)
                    .padding(.vertical, 12)
            }
            if isSearching && results.isEmpty {
                SkeletonRows(count: 4)
            }
            DividedList(filtered, inset: 40) { summary in
                NavigationLink(value: summary) { CourseRow(summary: summary) }
                    .buttonStyle(PressableStyle())
                    .transition(.opacity)
            }
            Text(OpenGolfAPIClient.attribution)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .animation(.gentle, value: results)
    }

    @ViewBuilder
    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Nearby", subtitle: "Golf, pitch & putt and mini golf around you")
            if app.location.isDenied {
                Label("Location is off. Enable it in Settings to find courses near you.", systemImage: "location.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else if nearby.isEmpty {
                Button {
                    Task { await loadNearby() }
                } label: {
                    HStack(spacing: 8) {
                        if isLoadingNearby { ProgressView() }
                        Label(isLoadingNearby ? "Looking around…" : "Find courses near me", systemImage: "location")
                    }
                }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.fairway))
                .disabled(isLoadingNearby)
                .padding(.top, 10)
            } else {
                DividedList(Array(filter(nearby).prefix(12)), inset: 40) { summary in
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
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Your courses")
                DividedList(courses, inset: 40) { summary in
                    NavigationLink(value: summary) { CourseRow(summary: summary, isFavorite: app.isFavorite(summary.id)) }
                        .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Demo courses", subtitle: "Fully mapped, good for trying replays and matches")
            DividedList(filter(DemoData.courses.map(\.summary)), inset: 40) { summary in
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
                .font(.body)
                .foregroundStyle(Theme.tint(for: type))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(summary.name).font(.body.weight(.medium)).lineLimit(1)
                    if isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.gold) }
                }
                Text(details).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let distanceText {
                Text(distanceText)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
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

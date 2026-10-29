import SwiftUI
import GolfKit

struct CourseDetailView: View {
    @Environment(AppModel.self) private var app
    let summary: CourseSummary

    @State private var course: Course?
    @State private var layout: CourseLayout?
    @State private var weather: WeatherReport?
    @State private var selectedTeeID: String?
    @State private var loadError: String?
    @State private var showSoloSetup = false
    @State private var showMatchSetup = false
    @State private var showEditor = false
    @State private var favoriteBounce = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if let course {
                    content(course)
                } else if let loadError {
                    EmptyStateView(title: "Couldn't load course", message: loadError, systemImage: "wifi.exclamationmark", actionTitle: "Try again") {
                        Task { await load() }
                    }
                    .cardStyle()
                    .padding(.horizontal)
                } else {
                    VStack(spacing: 12) {
                        LoadingCard(height: 60)
                        LoadingCard(height: 180)
                        LoadingCard(height: 140)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 30)
        }
        .background(Theme.background)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let course {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        favoriteBounce += 1
                        app.toggleFavorite(course)
                    } label: {
                        Image(systemName: app.isFavorite(course.id) ? "star.fill" : "star")
                            .foregroundStyle(Theme.gold)
                            .symbolEffect(.bounce, value: favoriteBounce)
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: favoriteBounce)
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showSoloSetup) {
            if let course { RoundSetupView(course: course, tee: selectedTee) }
        }
        .sheet(isPresented: $showMatchSetup) {
            if let course { CreateMatchView(course: course, tee: selectedTee) }
        }
        .sheet(isPresented: $showEditor) {
            if let course { CustomCourseEditor(existing: course) { updated in self.course = updated } }
        }
    }

    private var selectedTee: TeeSet? {
        course?.tees.first { $0.id == selectedTeeID } ?? course?.defaultTee
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let course, let layout {
                    CourseOverviewMap(course: course, layout: layout)
                        .transition(.opacity)
                } else {
                    Theme.gradient(for: course?.gameType ?? .golf)
                        .overlay {
                            Image(systemName: (course?.gameType ?? .golf).symbolName)
                                .font(.system(size: 90, weight: .bold))
                                .foregroundStyle(.white.opacity(0.15))
                        }
                }
            }
            .frame(height: 280)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                .frame(height: 280)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                Text(course?.name ?? summary.name)
                    .font(.rounded(30, weight: .heavy))
                    .lineLimit(2)
                if !(course?.locality ?? summary.locality).isEmpty {
                    Label(course?.locality ?? summary.locality, systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.9)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .animation(.easeInOut(duration: 0.6), value: layout != nil)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            facts(course)
            actions(course)
            if let weather {
                WeatherCard(report: weather, units: app.units)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !course.tees.isEmpty { teePicker(course) }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Scorecard", actionTitle: canEdit(course) ? "Edit" : nil) { showEditor = true }
                ScorecardGrid(course: course, holes: course.holes.map(\.number), tee: selectedTee, units: app.units)
            }
            CourseHistorySection(course: course)
            attribution(course)
        }
        .padding(.horizontal)
        .animation(.snappySpring, value: weather?.fetchedAt)
    }

    private func facts(_ course: Course) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                InfoPill(text: course.gameType.displayName, systemImage: course.gameType.symbolName, tint: Theme.tint(for: course.gameType))
                InfoPill(text: "\(course.holeCount) holes", systemImage: "flag")
                InfoPill(text: "Par \(course.par)", systemImage: "number")
                if let length = course.totalLength(for: selectedTee) {
                    InfoPill(text: app.units.courseLength(length), systemImage: "ruler")
                }
                if let tee = selectedTee, let rating = tee.courseRating, let slope = tee.slopeRating {
                    InfoPill(text: String(format: "%.1f / %d", rating, slope), systemImage: "gauge.with.dots.needle.50percent")
                }
                if let year = course.yearBuilt { InfoPill(text: "Est. \(year)", systemImage: "calendar") }
                if let access = course.accessType { InfoPill(text: access.capitalized, systemImage: "lock.open") }
            }
        }
    }

    private func actions(_ course: Course) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { showSoloSetup = true } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle(gradient: Theme.gradient(for: course.gameType)))

                Button { showMatchSetup = true } label: {
                    Label("Host match", systemImage: "person.3.fill")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.tint(for: course.gameType)))
            }
            if layout != nil {
                NavigationLink {
                    CourseMapView(course: course)
                } label: {
                    Label("Explore the course map", systemImage: "map.fill")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.water))
            }
        }
    }

    private func teePicker(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tees")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(course.tees) { tee in
                        let selected = tee.id == selectedTee?.id
                        Button {
                            withAnimation(.snappySpring) { selectedTeeID = tee.id }
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hexString: tee.colorHex) ?? .gray)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tee.name).font(.subheadline.weight(.bold))
                                    Text(teeDetail(tee)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(selected ? Theme.fairway.opacity(0.15) : Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Theme.fairway : .clear, lineWidth: 2))
                        }
                        .buttonStyle(PressableStyle())
                        .foregroundStyle(.primary)
                    }
                }
                .padding(2)
            }
        }
    }

    private func teeDetail(_ tee: TeeSet) -> String {
        var parts: [String] = []
        if let length = tee.totalLength { parts.append(app.units.courseLength(length)) }
        if let rating = tee.courseRating, let slope = tee.slopeRating { parts.append(String(format: "%.1f/%d", rating, slope)) }
        return parts.isEmpty ? "No rating" : parts.joined(separator: " · ")
    }

    private func attribution(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch course.source {
            case .openGolfAPI: Text(OpenGolfAPIClient.attribution)
            case .openStreetMap: Text(OverpassClient.attribution)
            case .custom, .demo: EmptyView()
            }
            if layout != nil && course.source != .demo { Text(OverpassClient.attribution) }
            if weather != nil { Text(OpenMeteoClient.attribution) }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private func canEdit(_ course: Course) -> Bool {
        course.source != .demo
    }

    // MARK: - Loading

    private func load() async {
        loadError = nil
        do {
            let loaded: Course
            if let known = app.library.course(id: summary.id) {
                loaded = known
            } else {
                loaded = try await app.loadCourse(summary)
            }
            withAnimation(.snappySpring) { course = loaded }
            if let location = loaded.location {
                let report = await app.weather(at: location)
                withAnimation(.snappySpring) { weather = report }
            }
            let mapped = await app.layout(for: loaded)
            withAnimation(.snappySpring) { layout = mapped }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Your history at this course: average, best, and per-hole difficulty.
struct CourseHistorySection: View {
    @Environment(AppModel.self) private var app
    let course: Course

    var body: some View {
        let rounds = app.library.completedRounds.filter { $0.course.id == course.id && $0.playerID == app.profile.id }
        if let stats = StatsEngine.courseStats(rounds: rounds).first {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Your record here", subtitle: "\(stats.roundsPlayed) round\(stats.roundsPlayed == 1 ? "" : "s")")
                HStack(spacing: 10) {
                    StatTile(title: "Best", value: stats.bestRound.map { "\($0.totalStrokes)" } ?? "—", subtitle: stats.bestRound.map { Leaderboard.formatToPar($0.toPar) }, systemImage: "trophy.fill", tint: Theme.gold)
                    StatTile(title: "Average", value: stats.averageScore.map { String(format: "%.1f", $0) } ?? "—", systemImage: "sum")
                    StatTile(title: "GIR", value: stats.scoring.greensInRegulation.percentText, systemImage: "scope", tint: Theme.water)
                }
                NavigationLink {
                    CourseStatsView(courseID: course.id)
                } label: {
                    Label("Hole-by-hole breakdown", systemImage: "square.grid.3x3.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

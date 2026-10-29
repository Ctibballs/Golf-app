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
            VStack(alignment: .leading, spacing: 0) {
                // A window onto the course map behind; the page slides up over it.
                Color.clear.frame(height: 190)
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    titleBlock
                    if let course {
                        content(course)
                    } else if let loadError {
                        EmptyStateView(title: "Couldn't load course", message: loadError, systemImage: "wifi.exclamationmark", actionTitle: "Try again") {
                            Task { await load() }
                        }
                    } else {
                        SkeletonRows(count: 4)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.background)
                .overlay(alignment: .top) { Hairline() }
            }
        }
        .background(alignment: .top) {
            hero
                .frame(height: 320)
                .clipped()
                .ignoresSafeArea(edges: .top)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let course {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        favoriteBounce += 1
                        app.toggleFavorite(course)
                    } label: {
                        Image(systemName: app.isFavorite(course.id) ? "star.fill" : "star")
                            .foregroundStyle(app.isFavorite(course.id) ? Theme.gold : .primary)
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

    // MARK: - Header

    private var hero: some View {
        Group {
            if let course, let layout {
                CourseOverviewMap(course: course, layout: layout)
                    .transition(.opacity)
            } else {
                Theme.surface
                    .overlay {
                        Image(systemName: (course?.gameType ?? .golf).symbolName)
                            .font(.system(size: 54, weight: .ultraLight))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .animation(.easeInOut(duration: 0.6), value: layout != nil)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(eyebrowText)
            Text(course?.name ?? summary.name)
                .font(.display(30))
                .lineLimit(3)
        }
        .reveal(0)
    }

    private var eyebrowText: String {
        let type = (course?.gameType ?? .golf).displayName
        let locality = course?.locality ?? summary.locality
        return locality.isEmpty ? type : "\(type) · \(locality)"
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            MetricGrid(items: facts(course), columns: 4, compact: true)
                .overlay(alignment: .top) { Hairline() }
                .overlay(alignment: .bottom) { Hairline() }
            actions(course)
        }
        .reveal(1)
        if let weather {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Conditions")
                WeatherPanel(report: weather, units: app.units)
            }
            .transition(.opacity)
        }
        if !course.tees.isEmpty { teePicker(course) }
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Scorecard", actionTitle: canEdit(course) ? "Edit" : nil) { showEditor = true }
            ScorecardGrid(course: course, holes: course.holes.map(\.number), tee: selectedTee, units: app.units)
        }
        CourseHistorySection(course: course)
        attribution(course)
    }

    private func facts(_ course: Course) -> [MetricItem] {
        var items = [
            MetricItem(label: "Holes", value: "\(course.holeCount)"),
            MetricItem(label: "Par", value: "\(course.par)"),
        ]
        if let length = course.totalLength(for: selectedTee) {
            items.append(MetricItem(label: "Length", value: app.units.courseLength(length)))
        }
        if let tee = selectedTee, let rating = tee.courseRating, let slope = tee.slopeRating {
            items.append(MetricItem(label: "Rating", value: String(format: "%.1f/%d", rating, slope)))
        } else if let year = course.yearBuilt {
            items.append(MetricItem(label: "Opened", value: "\(year)"))
        }
        return items
    }

    private func actions(_ course: Course) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { showSoloSetup = true } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button { showMatchSetup = true } label: {
                    Label("Host match", systemImage: "person.2")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            if layout != nil {
                NavigationLink {
                    CourseMapView(course: course)
                } label: {
                    NavigationRowLabel(title: "Course map", subtitle: "Every hole, with distances", systemImage: "map")
                }
                .buttonStyle(PressableStyle())
                .overlay(alignment: .bottom) { Hairline() }
            }
        }
    }

    private func teePicker(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Tees")
            DividedList(course.tees, inset: 26) { tee in
                let selected = tee.id == selectedTee?.id
                Button {
                    withAnimation(.snappySpring) { selectedTeeID = tee.id }
                } label: {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color(hexString: tee.colorHex) ?? .gray)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 0.5))
                        Text(tee.name).font(.body.weight(.medium))
                        Spacer()
                        Text(teeDetail(tee)).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.fairway)
                            .opacity(selected ? 1 : 0)
                            .scaleEffect(selected ? 1 : 0.5)
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
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
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Your record here", subtitle: "\(stats.roundsPlayed) round\(stats.roundsPlayed == 1 ? "" : "s")")
                MetricGrid(items: [
                    MetricItem(label: "Best", value: stats.bestRound.map { "\($0.totalStrokes)" } ?? "—", detail: stats.bestRound.map { Leaderboard.formatToPar($0.toPar) }),
                    MetricItem(label: "Average", value: stats.averageScore.map { String(format: "%.1f", $0) } ?? "—"),
                    MetricItem(label: "GIR", value: stats.scoring.greensInRegulation.percentText),
                ], columns: 3)
                Hairline()
                NavigationLink {
                    CourseStatsView(courseID: course.id)
                } label: {
                    NavigationRowLabel(title: "Hole-by-hole breakdown", systemImage: "square.grid.3x3")
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

import SwiftUI
import GolfKit

/// Sets up a solo round or a match lobby: course, tee, holes, format and handicaps.
struct RoundSetupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var course: Course?
    var tee: TeeSet?
    var startsAsMatch = false

    @State private var selectedCourse: Course?
    @State private var teeID: String?
    @State private var holeCount = 18
    @State private var startHole = 1
    @State private var courseOrigin: CourseOrigin = .none
    @State private var withFriends = false
    @State private var format: ScoringFormat = .strokePlay
    @State private var useHandicaps = true
    @State private var matchName = ""
    @State private var playInTeams = false
    @State private var teamFormat: TeamFormat = .fourBall
    @State private var teamCount = 2
    @State private var rulesShown: FormatRules?
    @State private var isCreating = false
    @State private var didSetUp = false

    /// Where the selected course came from, so a later location fix doesn't replace a choice.
    private enum CourseOrigin { case none, given, detected, recent, picked }

    private func holeNumbers(for course: Course) -> [Int] {
        HolePlan(count: holeCount, startHole: startHole).holeNumbers(for: course)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    courseSection
                    if let selectedCourse {
                        if !selectedCourse.tees.isEmpty { teeSection(selectedCourse) }
                        holesSection(selectedCourse)
                        playersSection
                        if withFriends { matchSection(selectedCourse) }
                        summary(selectedCourse)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
                .animation(.snappySpring, value: withFriends)
                .animation(.snappySpring, value: selectedCourse?.id)
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle(startsAsMatch ? "Host a match" : "New round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear(perform: setUp)
            .onChange(of: app.courseFinder.detection?.course.id) { adoptDetectedCourse() }
        }
    }

    // MARK: - Sections

    private var courseSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Course")
            NavigationLink {
                CoursePickerView { picked in
                    choose(picked, origin: .picked)
                }
            } label: {
                NavigationRowLabel(
                    title: selectedCourse?.name ?? "Choose a course",
                    subtitle: selectedCourse.map { "\($0.gameType.displayName) · \($0.holeCount) holes · Par \($0.par)" } ?? "Search, nearby or your own",
                    systemImage: selectedCourse?.gameType.symbolName ?? "magnifyingglass"
                )
            }
            .buttonStyle(PressableStyle())
            if courseOrigin == .detected {
                HStack(spacing: 8) {
                    LocationPulse(size: 8)
                    Text("Found from your location").font(.footnote).foregroundStyle(Theme.fairway)
                }
                .padding(.leading, 38)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if app.courseFinder.isSearching && course == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for the course you're at…").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.leading, 38)
            }
        }
        .animation(.snappySpring, value: courseOrigin == .detected)
    }

    private func teeSection(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Tee")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(course.tees) { tee in
                        Chip(title: tee.name, swatch: Color(hexString: tee.colorHex) ?? .gray, isSelected: tee.id == (teeID ?? course.defaultTee?.id)) {
                            teeID = tee.id
                        }
                    }
                }
                .padding(1)
            }
        }
    }

    private func holesSection(_ course: Course) -> some View {
        let numbers = holeNumbers(for: course)
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Holes", subtitle: HolePlan.describe(numbers)) {
                if course.holeCount < 18 {
                    Text("\(course.holeCount)-hole course").font(.caption).foregroundStyle(.secondary)
                }
            }
            if course.holeCount >= 18 {
                Picker("Holes", selection: $holeCount.animation(.snappySpring)) {
                    Text("18 holes").tag(18)
                    Text("9 holes").tag(9)
                }
                .pickerStyle(.segmented)
                if holeCount == 9 {
                    HStack(spacing: 8) {
                        Chip(title: "Front nine", isSelected: numbers == Array(1...9)) { withAnimation(.snappySpring) { startHole = 1 } }
                        Chip(title: "Back nine", isSelected: numbers == Array(10...18)) { withAnimation(.snappySpring) { startHole = 10 } }
                    }
                    .transition(.opacity)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("Start on hole")
                StartHolePicker(holes: course.holes.map(\.number), playing: Set(numbers), selection: $startHole)
            }
        }
    }

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Who's playing")
            RadioRow(title: "Just me", subtitle: "A solo round", systemImage: "person", isSelected: !withFriends) { withFriends = false }
            Hairline().padding(.leading, 38)
            RadioRow(title: "With friends", subtitle: "Share a four-letter join code", systemImage: "person.2", isSelected: withFriends) { withFriends = true }
        }
    }

    private func matchSection(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Match")
            UnderlineField(title: "Name", text: $matchName)
                .padding(.vertical, 10)
            DividedList(availableFormats, inset: 38) { option in
                RadioRow(title: option.displayName, subtitle: option.summary, systemImage: option.symbolName, isSelected: format == option) {
                    format = option
                }
                .contextMenu {
                    Button("How \(option.displayName) works", systemImage: "book") { rulesShown = FormatRules.rules(for: option) }
                }
            }
            Hairline()
            Toggle(isOn: $playInTeams.animation(.snappySpring)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Play in teams").font(.body.weight(.medium))
                    Text("Four-ball, best ball, scramble, foursomes and Chapman").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .tint(Theme.fairway)
            .padding(.vertical, 12)
            .onChange(of: playInTeams) { _, teams in
                if teams && format == .skins { format = .strokePlay }
            }
            if playInTeams {
                teamOptions
            }
            Hairline()
            Toggle(isOn: $useHandicaps) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use handicaps").font(.body.weight(.medium))
                    Text("Net scores using each player's index").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .tint(Theme.fairway)
            .padding(.vertical, 12)
            if useHandicaps && !app.handicap(for: course.gameType).isEnabled {
                Label("Your handicap is switched off, so you'll play off scratch.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !app.isOnline {
                Label("Offline demo: simulated friends will join your lobby. Set up online play in Settings to play real friends.", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            Hairline().padding(.top, 8)
            NavigationLink {
                RulesView()
            } label: {
                NavigationRowLabel(title: "How each format works", subtitle: "Rules, scoring and handicap allowances", systemImage: "book")
            }
            .buttonStyle(PressableStyle())
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .sheet(item: $rulesShown) { RuleSheet(rule: $0) }
    }

    /// Skins is an individual game, so it's left out when playing in teams.
    private var availableFormats: [ScoringFormat] {
        playInTeams ? ScoringFormat.allCases.filter { $0 != .skins } : ScoringFormat.allCases
    }

    private var teamOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Team format").padding(.top, 4).padding(.bottom, 2)
            DividedList(TeamFormat.allCases, inset: 38) { option in
                RadioRow(title: option.displayName, subtitle: option.summary, systemImage: option.symbolName, isSelected: teamFormat == option) {
                    teamFormat = option
                    if format != .matchPlay { teamCount = option.usualTeamSize == 2 ? 2 : teamCount }
                }
                .contextMenu {
                    Button("How \(option.displayName) works", systemImage: "book") { rulesShown = FormatRules.rules(for: option) }
                }
            }
            Hairline()
            Stepper(value: $teamCount, in: 2...(format == .matchPlay ? 2 : 4)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(teamCount) teams").font(.body.weight(.medium)).monospacedDigit()
                    Text(format == .matchPlay ? "Match play is one side against the other." : "Pick who's on which team in the lobby, or let Fairway balance them by handicap.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)
            .onChange(of: format) { _, newFormat in
                if newFormat == .matchPlay { teamCount = 2 }
            }
            Button {
                rulesShown = FormatRules.rules(for: teamFormat)
            } label: {
                Label("How \(teamFormat.displayName) works", systemImage: "book")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.fairway)
            }
            .buttonStyle(PressableStyle())
            .padding(.bottom, 8)
        }
        .transition(.opacity)
    }

    private func summary(_ course: Course) -> some View {
        let numbers = holeNumbers(for: course)
        let tee = selectedTee(course)
        let lengths = numbers.compactMap { course.hole($0)?.length(for: tee) }
        let totalLength: Double? = lengths.isEmpty ? nil : lengths.reduce(0, +)
        let strokes = courseHandicap(course, tee: tee, holes: numbers)
        var items = [MetricItem(label: "Par", value: "\(course.par(for: numbers))", detail: "\(numbers.count) holes")]
        if let totalLength {
            items.append(MetricItem(label: "Length", value: app.units.distanceNumber(totalLength), detail: app.units.system.distanceUnit))
        }
        if let strokes {
            items.append(MetricItem(label: "Strokes", value: "\(strokes)", detail: "Course handicap"))
        }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Summary")
            MetricGrid(items: items, columns: 3)
        }
    }

    private func courseHandicap(_ course: Course, tee: TeeSet?, holes numbers: [Int]) -> Int? {
        guard let index = app.handicap(for: course.gameType).index else { return nil }
        guard course.gameType == .golf else {
            return CasualHandicapCalculator.courseHandicap(index: index, holes: numbers.count)
        }
        var rating = tee?.courseRating
        if let r = rating, numbers.count <= 9, course.holeCount >= 18 { rating = r / 2 }
        return HandicapCalculator.courseHandicap(index: index, slope: tee?.slopeRating, courseRating: rating, par: course.par(for: numbers), holes: numbers.count)
    }

    private var footer: some View {
        Button {
            Task { await start() }
        } label: {
            HStack {
                if isCreating { ProgressView().tint(Theme.onAccent) }
                Text(withFriends ? "Create lobby" : "Tee off")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(selectedCourse == nil || isCreating)
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 10)
        .background(Theme.background)
        .overlay(alignment: .top) { Hairline() }
    }

    // MARK: - Actions

    private func selectedTee(_ course: Course) -> TeeSet? {
        course.tees.first { $0.id == teeID } ?? course.defaultTee
    }

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        withFriends = startsAsMatch
        matchName = "\(app.profile.name)'s round"
        if let course {
            choose(course, origin: .given)
            if let tee { teeID = tee.id }
        } else if let detected = app.courseFinder.detection?.course {
            choose(detected, origin: .detected)
        } else if let recent = app.library.completedRounds.first?.course {
            choose(recent, origin: .recent)
        }
        // A fresh fix, in case you've just arrived at a course.
        if course == nil && app.library.settings.detectCourse { app.location.requestOneShot() }
    }

    private func choose(_ picked: Course, origin: CourseOrigin) {
        withAnimation(.snappySpring) {
            selectedCourse = picked
            courseOrigin = origin
            teeID = picked.defaultTee?.id
            if !picked.holes.contains(where: { $0.number == startHole }) { startHole = picked.holes.first?.number ?? 1 }
        }
    }

    /// Switches to the course you're at when it's found, unless you've chosen one yourself.
    private func adoptDetectedCourse() {
        guard let detected = app.courseFinder.detection?.course,
              courseOrigin == .none || courseOrigin == .recent,
              detected.id != selectedCourse?.id else { return }
        choose(detected, origin: .detected)
    }

    private func start() async {
        guard let course = selectedCourse else { return }
        let numbers = holeNumbers(for: course)
        let tee = selectedTee(course)
        if withFriends {
            isCreating = true
            defer { isCreating = false }
            do {
                let session = try await app.createMatch(
                    name: matchName.isEmpty ? course.name : matchName, course: course, tee: tee,
                    holes: numbers, format: format, useHandicaps: useHandicaps,
                    teamFormat: playInTeams ? teamFormat : nil, teamCount: format == .matchPlay ? 2 : teamCount
                )
                dismiss()
                app.present(.match(session.id), afterDismissing: true)
            } catch {
                app.showError(error)
            }
        } else {
            let round = app.startSoloRound(course: course, tee: tee, holes: numbers)
            dismiss()
            app.present(.round(round.id), afterDismissing: true)
        }
    }
}

/// Host a match: the same setup, starting in group mode.
struct CreateMatchView: View {
    var course: Course?
    var tee: TeeSet?

    var body: some View {
        RoundSetupView(course: course, tee: tee, startsAsMatch: true)
    }
}

/// Pick a course inside a setup flow.
struct CoursePickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onPick: (Course) -> Void

    @State private var query = ""
    @State private var results: [CourseSummary] = []
    @State private var loadingID: String?
    @State private var showEditor = false

    var body: some View {
        List {
            if !results.isEmpty {
                Section("Search results") {
                    ForEach(results) { summary in row(summary) }
                }
            }
            let known = app.library.knownCourses
            if !known.isEmpty {
                Section("Your courses") {
                    ForEach(known) { course in row(course.summary) }
                }
            }
            Section("Demo courses") {
                ForEach(DemoData.courses) { course in row(course.summary) }
            }
            Section {
                Button {
                    showEditor = true
                } label: {
                    Label("Create a course", systemImage: "plus")
                }
            } footer: {
                Text("Handy for mini golf, pitch & putt or anywhere that isn't listed.")
            }
        }
        .flatList()
        .navigationTitle("Choose course")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search courses")
        .task(id: query) {
            guard query.count >= 2 else { results = []; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            results = (try? await app.searchCourses(query)) ?? []
        }
        .sheet(isPresented: $showEditor) {
            CustomCourseEditor { course in
                onPick(course)
                dismiss()
            }
        }
    }

    private func row(_ summary: CourseSummary) -> some View {
        Button {
            Task { await pick(summary) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(summary.locality.isEmpty ? (summary.par.map { "Par \($0)" } ?? "") : summary.locality)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if loadingID == summary.id { ProgressView() }
            }
        }
        .disabled(loadingID != nil)
    }

    private func pick(_ summary: CourseSummary) async {
        loadingID = summary.id
        defer { loadingID = nil }
        do {
            let course: Course
            if let known = app.library.course(id: summary.id) {
                course = known
            } else {
                course = try await app.loadCourse(summary)
            }
            onPick(course)
            dismiss()
        } catch {
            app.showError(error)
        }
    }
}

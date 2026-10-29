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
    @State private var holes: HoleSelection = .all
    @State private var withFriends = false
    @State private var format: ScoringFormat = .strokePlay
    @State private var useHandicaps = true
    @State private var matchName = ""
    @State private var isCreating = false
    @State private var didSetUp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    courseSection
                    if let selectedCourse {
                        if !selectedCourse.tees.isEmpty { teeSection(selectedCourse) }
                        if selectedCourse.holeCount >= 18 { holesSection }
                        playersSection
                        if withFriends { matchSection(selectedCourse) }
                        summary(selectedCourse)
                    }
                }
                .padding()
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
        }
    }

    // MARK: - Sections

    private var courseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Course")
            NavigationLink {
                CoursePickerView { picked in
                    selectedCourse = picked
                    teeID = picked.defaultTee?.id
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: selectedCourse?.gameType.symbolName ?? "magnifyingglass")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Theme.gradient(for: selectedCourse?.gameType ?? .golf), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedCourse?.name ?? "Choose a course").font(.headline)
                        Text(selectedCourse.map { "\($0.gameType.displayName) · \($0.holeCount) holes · Par \($0.par)" } ?? "Search, nearby or your own")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .cardStyle(padding: 12)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func teeSection(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tee")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(course.tees) { tee in
                        Chip(title: tee.name, systemImage: "circle.fill", isSelected: tee.id == (teeID ?? course.defaultTee?.id), tint: Color(hexString: tee.colorHex) ?? Theme.fairway) {
                            teeID = tee.id
                        }
                    }
                }
                .padding(2)
            }
        }
    }

    private var holesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Holes")
            Picker("Holes", selection: $holes) {
                ForEach(HoleSelection.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Who's playing?")
            HStack(spacing: 10) {
                modeCard(title: "Just me", subtitle: "Solo round", systemImage: "person.fill", selected: !withFriends) { withFriends = false }
                modeCard(title: "With friends", subtitle: "Share a join code", systemImage: "person.3.fill", selected: withFriends) { withFriends = true }
            }
        }
    }

    private func modeCard(title: String, subtitle: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage).font(.title3.weight(.semibold))
                Text(title).font(.headline)
                Text(subtitle).font(.caption).opacity(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .foregroundStyle(selected ? .white : .primary)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Theme.heroGradient) : AnyShapeStyle(Theme.card))
            }
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func matchSection(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Match")
            TextField("Match name", text: $matchName)
                .font(.headline)
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(spacing: 8) {
                ForEach(ScoringFormat.allCases) { option in
                    Button {
                        format = option
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.symbolName)
                                .font(.headline)
                                .frame(width: 32)
                                .foregroundStyle(format == option ? Theme.fairway : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.displayName).font(.subheadline.weight(.semibold))
                                Text(option.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: format == option ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(format == option ? Theme.fairway : Color.secondary.opacity(0.5))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .foregroundStyle(.primary)
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            Toggle(isOn: $useHandicaps) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use handicaps").font(.subheadline.weight(.semibold))
                    Text("Net scores using each player's index").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !app.isOnline {
                Label("Offline demo: simulated friends will join your lobby. Set up online play in Settings to play with real friends.", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func summary(_ course: Course) -> some View {
        let numbers = holes.holeNumbers(for: course)
        let tee = selectedTee(course)
        let lengths = numbers.compactMap { course.hole($0)?.length(for: tee) }
        let totalLength: Double? = lengths.isEmpty ? nil : lengths.reduce(0, +)
        let strokes = courseHandicap(course, tee: tee, holes: numbers)
        return HStack(spacing: 10) {
            StatTile(title: "Par", value: "\(course.par(for: numbers))", subtitle: "\(numbers.count) holes", systemImage: "flag.fill")
            if let totalLength {
                StatTile(title: "Length", value: app.units.distanceNumber(totalLength), subtitle: app.units.system.distanceUnit, systemImage: "ruler", tint: Theme.water)
            }
            if let strokes {
                StatTile(title: "Strokes", value: "\(strokes)", subtitle: "Course hcp", systemImage: "plusminus", tint: Theme.gold)
            }
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
                if isCreating { ProgressView().tint(.white) }
                Text(withFriends ? "Create lobby" : "Tee off")
            }
        }
        .buttonStyle(PrimaryButtonStyle(gradient: Theme.gradient(for: selectedCourse?.gameType ?? .golf)))
        .disabled(selectedCourse == nil || isCreating)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Actions

    private func selectedTee(_ course: Course) -> TeeSet? {
        course.tees.first { $0.id == teeID } ?? course.defaultTee
    }

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        selectedCourse = course ?? app.library.completedRounds.first?.course
        teeID = tee?.id ?? selectedCourse?.defaultTee?.id
        withFriends = startsAsMatch
        matchName = "\(app.profile.name)'s round"
    }

    private func start() async {
        guard let course = selectedCourse else { return }
        let numbers = holes.holeNumbers(for: course)
        let tee = selectedTee(course)
        if withFriends {
            isCreating = true
            defer { isCreating = false }
            do {
                let session = try await app.createMatch(
                    name: matchName.isEmpty ? course.name : matchName, course: course, tee: tee,
                    holes: numbers, format: format, useHandicaps: useHandicaps
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
                    Label("Create a course", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Handy for mini golf, pitch & putt or anywhere that isn't listed.")
            }
        }
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

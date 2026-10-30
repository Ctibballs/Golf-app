import SwiftUI
import GolfKit

struct CreateTournamentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var gameType: GameType = .golf
    @State private var format: ScoringFormat = .strokePlay
    @State private var useHandicaps = true
    @State private var roundCount = 2
    @State private var courses: [Int: Course] = [:]
    @State private var holeCount = 18
    @State private var startHole = 1
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Tournament name", text: $name)
                        .font(.headline)
                    Picker("Game", selection: $gameType) {
                        ForEach(GameType.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Event")
                }

                Section {
                    Picker("Format", selection: $format) {
                        Text(ScoringFormat.strokePlay.displayName).tag(ScoringFormat.strokePlay)
                        Text(ScoringFormat.stableford.displayName).tag(ScoringFormat.stableford)
                    }
                    Toggle("Use handicaps (net)", isOn: $useHandicaps)
                    Stepper(value: $roundCount, in: 1...4) {
                        LabeledContent("Rounds", value: "\(roundCount)")
                    }
                } header: {
                    Text("Scoring")
                } footer: {
                    Text(format == .stableford ? "Points add up across rounds." : "Lowest total score to par across all rounds wins.")
                }

                Section {
                    ForEach(1...roundCount, id: \.self) { number in
                        NavigationLink {
                            CoursePickerView { course in
                                courses[number] = course
                                // Fill later rounds with the same course until they're changed.
                                for later in (number + 1)...max(number + 1, 4) where courses[later] == nil {
                                    courses[later] = course
                                }
                            }
                        } label: {
                            LabeledContent("Round \(number)", value: courses[number]?.name ?? "Choose course")
                        }
                    }
                } header: {
                    Text("Courses")
                }

                Section {
                    Picker("Holes", selection: $holeCount) {
                        Text("18 holes").tag(18)
                        Text("9 holes").tag(9)
                    }
                    .pickerStyle(.segmented)
                    Picker("Start on hole", selection: $startHole) {
                        ForEach(1...maxHoles, id: \.self) { Text("Hole \($0)").tag($0) }
                    }
                } header: {
                    Text("Holes")
                } footer: {
                    Text("Every round plays \(holeCount == 18 ? "the full course" : "nine holes") from hole \(startHole), carrying on round the course. A nine-hole course plays its nine.")
                }

                Section {
                    Label("Players join with the tournament code. Each round opens as a live match everyone plays into, with a leaderboard showing every player's current hole.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .flatList()
            .navigationTitle("New tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Create") { Task { await create() } }
                            .disabled(!canCreate)
                    }
                }
            }
            .onAppear {
                if name.isEmpty { name = "\(app.profile.name)'s Open" }
                // Start from the course you're at, or the one you played last.
                if courses[1] == nil, let here = app.courseFinder.detection?.course, here.gameType == gameType {
                    courses[1] = here
                } else if courses[1] == nil, let recent = app.library.completedRounds.first(where: { $0.gameType == gameType })?.course {
                    courses[1] = recent
                }
            }
            .onChange(of: gameType) {
                courses = [:]
            }
        }
    }

    /// The most holes any chosen course has, for the starting-hole list.
    private var maxHoles: Int {
        max(1, courses.values.map(\.holeCount).max() ?? 18)
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (1...roundCount).allSatisfy { courses[$0] != nil }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        let rounds = (1...roundCount).map { number in
            TournamentRound(
                number: number, course: courses[number], tee: courses[number]?.defaultTee,
                holeNumbers: courses[number].map { HolePlan(count: holeCount, startHole: startHole).holeNumbers(for: $0) }
            )
        }
        do {
            let session = try await app.createTournament(
                name: name.trimmingCharacters(in: .whitespaces), gameType: gameType,
                format: format, useHandicaps: useHandicaps, rounds: rounds
            )
            dismiss()
            app.present(.tournament(session.id), afterDismissing: true)
        } catch {
            app.showError(error)
        }
    }
}

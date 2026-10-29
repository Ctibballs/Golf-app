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
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
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
                    Label("Players join with the tournament code. Each round opens as a live match everyone plays into, with a leaderboard showing every player's current hole.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
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
                if courses[1] == nil, let recent = app.library.completedRounds.first(where: { $0.gameType == gameType })?.course {
                    courses[1] = recent
                }
            }
            .onChange(of: gameType) {
                courses = [:]
            }
        }
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (1...roundCount).allSatisfy { courses[$0] != nil }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        let rounds = (1...roundCount).map { number in
            TournamentRound(number: number, course: courses[number], tee: courses[number]?.defaultTee)
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

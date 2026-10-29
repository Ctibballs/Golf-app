import SwiftUI
import GolfKit

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @State private var editing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { editing = true } label: {
                        HStack(spacing: 16) {
                            AvatarView(avatar: app.profile.avatar, size: 60)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.profile.name).font(.display(26))
                                Text("\(app.library.completedRounds.count) rounds · \(app.library.matchHistory.count) matches")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Edit").font(.subheadline.weight(.medium)).foregroundStyle(Theme.fairway)
                        }
                        .padding(.vertical, 8)
                    }
                    .foregroundStyle(.primary)
                }

                Section("Handicap") {
                    ForEach(GameType.allCases) { type in
                        NavigationLink {
                            HandicapView(gameType: type)
                        } label: {
                            let result = app.handicap(for: type)
                            HStack {
                                Label(type.displayName, systemImage: type.symbolName)
                                Spacer()
                                if result.index == nil {
                                    Text("\(result.roundsUntilEstablished) to go").font(.caption).foregroundStyle(.secondary)
                                }
                                Text(result.displayIndex)
                                    .font(.figure(17, weight: .semibold))
                            }
                        }
                    }
                }

                Section("Rounds") {
                    NavigationLink {
                        RoundHistoryView()
                    } label: {
                        Label("Round history", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink {
                        CustomCoursesView()
                    } label: {
                        Label("My courses", systemImage: "map")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About & data sources", systemImage: "info.circle")
                    }
                }
            }
            .flatList()
            .navigationTitle("Profile")
            .navigationDestination(for: Round.self) { RoundDetailView(roundID: $0.id) }
            .sheet(isPresented: $editing) { EditProfileView() }
        }
    }
}

struct EditProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar = Avatar(emoji: "⛳️", colorIndex: 0)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        AvatarView(avatar: avatar, size: 96)
                            .animation(.snappySpring, value: avatar)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
                Section("Name") {
                    TextField("Name", text: $name)
                }
                Section("Avatar") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(Avatar.emojiChoices, id: \.self) { emoji in
                            Text(emoji)
                                .font(.title2)
                                .frame(width: 36, height: 36)
                                .overlay(Circle().strokeBorder(avatar.emoji == emoji ? Theme.fairway : .clear, lineWidth: 1.5))
                                .onTapGesture { avatar.emoji = emoji }
                        }
                    }
                    HStack {
                        ForEach(0..<Theme.avatarPalette.count, id: \.self) { index in
                            Circle()
                                .fill(Theme.avatarColor(index))
                                .frame(width: 28, height: 28)
                                .padding(3)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: avatar.colorIndex == index ? 1.5 : 0))
                                .onTapGesture { avatar.colorIndex = index }
                        }
                    }
                }
            }
            .flatList()
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        // Read current state before mutating to avoid overlapping access.
                        let newName = trimmed.isEmpty ? app.profile.name : trimmed
                        let newAvatar = avatar
                        app.update {
                            $0.profile?.name = newName
                            $0.profile?.avatar = newAvatar
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = app.profile.name
                avatar = app.profile.avatar
            }
        }
    }
}

struct RoundHistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var filter: GameType?

    var body: some View {
        let rounds = app.library.completedRounds.filter { filter == nil || $0.gameType == filter }
        List {
            Section {
                Picker("Game", selection: $filter) {
                    Text("All").tag(GameType?.none)
                    ForEach(GameType.allCases) { Text($0.displayName).tag(GameType?.some($0)) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
            }
            ForEach(rounds) { round in
                NavigationLink(value: round) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(round.course.name).font(.subheadline.weight(.semibold))
                            Text("\(round.date.formatted(date: .abbreviated, time: .omitted)) · \(round.holesPlayed) holes\(round.countsForHandicap ? "" : " · casual")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(round.totalStrokes)").font(.figure(17, weight: .semibold))
                        ToParText(toPar: round.toPar, font: .footnote.weight(.medium)).frame(width: 34, alignment: .trailing)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { app.deleteRound(round.id) }
                }
            }
        }
        .flatList()
        .navigationTitle("Round history")
        .overlay {
            if rounds.isEmpty {
                ContentUnavailableView("No rounds", systemImage: "flag", description: Text("Finished rounds show up here."))
            }
        }
    }
}

struct CustomCoursesView: View {
    @Environment(AppModel.self) private var app
    @State private var showEditor = false
    @State private var editing: Course?

    var body: some View {
        List {
            ForEach(app.library.customCourses + app.library.savedCourses) { course in
                Button { editing = course } label: {
                    HStack {
                        Image(systemName: course.gameType.symbolName).foregroundStyle(Theme.tint(for: course.gameType))
                        VStack(alignment: .leading) {
                            Text(course.name).font(.subheadline.weight(.semibold))
                            Text("\(course.holeCount) holes · Par \(course.par)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        app.update {
                            $0.customCourses.removeAll { $0.id == course.id }
                            $0.savedCourses.removeAll { $0.id == course.id }
                            $0.favoriteCourseIDs.removeAll { $0 == course.id }
                        }
                    }
                }
            }
        }
        .flatList()
        .navigationTitle("My courses")
        .toolbar {
            Button { showEditor = true } label: { Image(systemName: "plus") }
        }
        .overlay {
            if app.library.customCourses.isEmpty && app.library.savedCourses.isEmpty {
                ContentUnavailableView("No courses yet", systemImage: "map", description: Text("Courses you create, play or favourite appear here."))
            }
        }
        .sheet(isPresented: $showEditor) { CustomCourseEditor() }
        .sheet(item: $editing) { course in CustomCourseEditor(existing: course) }
    }
}

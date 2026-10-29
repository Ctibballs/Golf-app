import SwiftUI
import GolfKit

/// Create a course (great for mini golf and pitch & putt) or fix pars on a downloaded one.
struct CustomCourseEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var existing: Course?
    var onSave: ((Course) -> Void)?

    @State private var name = ""
    @State private var gameType: GameType = .miniGolf
    @State private var pars: [Int] = Array(repeating: 2, count: 18)
    @State private var useLocation = true
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Course") {
                    TextField("Name", text: $name)
                        .font(.headline)
                    if existing == nil {
                        Picker("Type", selection: $gameType) {
                            ForEach(GameType.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: gameType) { _, type in
                            pars = Array(repeating: type.defaultPar, count: pars.count)
                        }
                    }
                }

                Section {
                    Stepper(value: holeCount, in: 1...36) {
                        HStack {
                            Text("Holes")
                            Spacer()
                            Text("\(pars.count)").font(.headline).contentTransition(.numericText(value: Double(pars.count)))
                        }
                    }
                    HStack {
                        ForEach([9, 18], id: \.self) { count in
                            Chip(title: "\(count) holes", isSelected: pars.count == count) {
                                withAnimation(.snappySpring) { holeCount.wrappedValue = count }
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    Text("Layout")
                } footer: {
                    Text("Tap a hole to cycle its par. Total par \(pars.reduce(0, +)).")
                }

                Section("Pars") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                        ForEach(pars.indices, id: \.self) { index in
                            Button {
                                cyclePar(index)
                            } label: {
                                VStack(spacing: 2) {
                                    Text("\(index + 1)").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                                    Text("\(pars[index])")
                                        .font(.rounded(20, weight: .heavy))
                                        .contentTransition(.numericText(value: Double(pars[index])))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Theme.tint(for: gameType).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }

                if existing == nil {
                    Section {
                        Toggle("Pin to my current location", isOn: $useLocation)
                    } footer: {
                        Text("Lets Fairway show the weather and, for outdoor courses, distances on the map.")
                    }
                }
            }
            .navigationTitle(existing == nil ? "New course" : "Edit scorecard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: loadExisting)
        }
        .presentationDragIndicator(.visible)
    }

    private var holeCount: Binding<Int> {
        Binding(
            get: { pars.count },
            set: { newCount in
                if newCount > pars.count {
                    pars += Array(repeating: gameType.defaultPar, count: newCount - pars.count)
                } else {
                    pars = Array(pars.prefix(newCount))
                }
            }
        )
    }

    private func cyclePar(_ index: Int) {
        let range = gameType.allowedPars
        let next = pars[index] + 1
        withAnimation(.snappySpring) {
            pars[index] = range.contains(next) ? next : range.lowerBound
        }
    }

    private func loadExisting() {
        guard !didLoad else { return }
        didLoad = true
        if let existing {
            name = existing.name
            gameType = existing.gameType
            pars = existing.holes.map(\.par)
        } else {
            app.location.requestOneShot()
        }
    }

    private func save() {
        var course: Course
        if let original = existing {
            course = original
            course.name = name
            course.holes = pars.enumerated().map { index, par in
                var hole = original.hole(index + 1) ?? HoleInfo(number: index + 1, par: par)
                hole.par = par
                return hole
            }
        } else {
            course = Course.custom(
                name: name.trimmingCharacters(in: .whitespaces),
                gameType: gameType,
                pars: pars,
                location: useLocation ? app.location.point : nil
            )
        }
        course.name = course.name.trimmingCharacters(in: .whitespaces)
        app.saveCourse(course)
        onSave?(course)
        app.show(Banner(title: "Course saved", message: course.name, style: .success))
        dismiss()
    }
}

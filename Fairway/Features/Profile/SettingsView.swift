import SwiftUI
import GolfKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    @State private var project = ""
    @State private var anonKey = ""
    @State private var apiKey = ""
    @State private var testing = false
    @State private var testResult: String?
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                Picker("Units", selection: app.binding(\.settings.units)) {
                    ForEach(UnitSystem.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Example", value: "\(app.units.distance(150)) · \(app.units.temperature(18, includeUnit: true)) · \(app.units.windSpeed(20))")
                    .contentTransition(.numericText())
                    .animation(.snappySpring, value: app.library.settings.units)
            } header: {
                Text("Units")
            } footer: {
                Text("Metric is the default. Everything is stored in metric and converted for display.")
            }

            Section("On the course") {
                Toggle("Haptics", isOn: app.binding(\.settings.haptics))
                Toggle("Detect lie from the map", isOn: app.binding(\.settings.autoDetectLie))
                Toggle("Keep screen awake while playing", isOn: app.binding(\.settings.keepScreenAwake))
                Toggle("Share my position with my group", isOn: app.binding(\.settings.online.shareLiveLocation))
            }

            Section {
                HStack {
                    Label(app.isOnline ? "Connected to Supabase" : "Offline demo mode", systemImage: app.isOnline ? "checkmark.circle.fill" : "wifi.slash")
                        .foregroundStyle(app.isOnline ? Theme.fairway : .secondary)
                    Spacer()
                    if app.isOnline && testing { ProgressView() }
                }
                TextField("Project ref or URL", text: $project)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Anon public key", text: $anonKey)
                Button("Save & connect") {
                    let online = OnlineSettings(
                        supabaseProject: project, supabaseAnonKey: anonKey,
                        openGolfAPIKey: app.library.settings.online.openGolfAPIKey,
                        shareLiveLocation: app.library.settings.online.shareLiveLocation
                    )
                    app.update {
                        $0.settings.online = online
                        $0.supabaseSession = nil
                    }
                    app.reconfigureOnline()
                    Task { await testConnection() }
                }
                .disabled((project.isEmpty) != (anonKey.isEmpty))
                if app.isOnline {
                    Button("Test connection") { Task { await testConnection() } }
                }
                if let testResult {
                    Text(testResult).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Online play")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Real matches and tournaments sync through a free Supabase project. Create one at supabase.com, run supabase/schema.sql from this repo in the SQL editor, enable anonymous sign-ins, then paste the project ref and anon key here. Everyone you play with needs the same settings (or bake them into OnlineConfig.swift).")
                    Text("Leave both empty for offline demo mode with simulated friends.")
                }
            }

            Section {
                SecureField("OpenGolfAPI key (optional)", text: $apiKey)
                    .onSubmit(saveAPIKey)
                Button("Save key", action: saveAPIKey)
            } header: {
                Text("Course data")
            } footer: {
                Text("Course search works without a key (1,000 requests a day). A free key from opengolfapi.org raises the limit.")
            }

            Section("Data") {
                if app.library.hasSampleData {
                    Button("Remove sample rounds") { app.removeSampleData() }
                } else {
                    Button("Load sample rounds") { app.loadSampleData() }
                }
                Button("Reset everything", role: .destructive) { confirmReset = true }
            }
        }
        .flatList()
        .navigationTitle("Settings")
        .onAppear {
            project = app.library.settings.online.supabaseProject
            anonKey = app.library.settings.online.supabaseAnonKey
            apiKey = app.library.settings.online.openGolfAPIKey
        }
        .confirmationDialog("Reset everything?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Delete all rounds and settings", role: .destructive) {
                app.update { $0 = GolfLibrary() }
                app.reconfigureOnline()
            }
        } message: {
            Text("This removes your profile, rounds, matches and courses from this device.")
        }
    }

    private func saveAPIKey() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        app.update { $0.settings.online.openGolfAPIKey = key }
        app.show(Banner(title: key.isEmpty ? "API key removed" : "API key saved", style: .success))
    }

    private func testConnection() async {
        guard app.isOnline else {
            testResult = "Offline demo mode is active."
            return
        }
        testing = true
        defer { testing = false }
        do {
            _ = try await app.matchService.snapshot(matchID: UUID())
            testResult = "Connected."
        } catch MatchServiceError.notFound {
            testResult = "Connected — signed in anonymously and the tables are reachable."
        } catch {
            testResult = "Couldn't connect: \(error.localizedDescription)"
        }
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        FlagMark().frame(width: 40, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fairway").font(.display(28))
                            Text("Golf, pitch & putt and mini golf with friends").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Text("Built on free and open data. No ads, no accounts, no subscriptions.")
                        .font(.subheadline)
                }
                .padding(.vertical, 8)
            }

            Section("Data sources") {
                source("OpenGolfAPI", detail: OpenGolfAPIClient.attribution, url: "https://opengolfapi.org")
                source("OpenStreetMap", detail: "Hole maps via the Overpass API. \(OverpassClient.attribution)", url: "https://www.openstreetmap.org/copyright")
                source("Open-Meteo", detail: OpenMeteoClient.attribution, url: "https://open-meteo.com")
                source("Apple Maps", detail: "Satellite imagery and base maps through MapKit.", url: "https://www.apple.com/maps/")
                source("Supabase (optional)", detail: "Your own free project syncs matches and tournaments.", url: "https://supabase.com")
            }

            Section("Missing holes?") {
                Text("Hole maps come from OpenStreetMap volunteers. If your course isn't mapped yet, you can trace it at openstreetmap.org (tags golf=hole, golf=green, golf=tee, golf=fairway, golf=bunker) and it will appear in Fairway.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .flatList()
        .navigationTitle("About")
    }

    private func source(_ name: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let link = URL(string: url) {
                Link(name, destination: link).font(.body.weight(.medium)).tint(Theme.fairway)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

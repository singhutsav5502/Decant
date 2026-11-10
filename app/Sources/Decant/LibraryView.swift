import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library grid

struct LibraryView: View {
    @Environment(Store.self) private var store
    var openBottle: (String) -> Void
    @State private var search = ""
    @State private var addingGame = false
    @State private var confirmSteam = false

    private var shown: [Game] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return store.games
            .filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
            .sorted { ($0.running ? 0 : 1, $0.name.lowercased()) < ($1.running ? 0 : 1, $1.name.lowercased()) }
    }

    var body: some View {
        Group {
            if store.games.isEmpty {
                ContentUnavailableView {
                    Label("No games yet", systemImage: "gamecontroller")
                } description: {
                    Text("Install games through Steam, or add any Windows game or installer (.exe) you've downloaded.")
                } actions: {
                    HStack {
                        Button("Add Game…") { addingGame = true }.buttonStyle(.borderedProminent)
                        steamButton
                    }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 20)], spacing: 24) {
                        ForEach(shown) { game in
                            GameCard(game: game, openBottle: openBottle)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle("Library")
        .searchable(text: $search, placement: .toolbar, prompt: "Search games")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                steamButton
                Button { addingGame = true } label: { Label("Add Game", systemImage: "plus") }
                    .help("Add a downloaded Windows game or run its installer")
            }
        }
        .sheet(isPresented: $addingGame) { AddGameSheet() }
        .confirmationDialog("Install Steam?", isPresented: $confirmSteam) {
            Button("Download and Install") { Task { await installSteam() } }
        } message: {
            Text("Downloads the Steam installer (about 2 MB) from Valve and installs it into your default bottle (\(store.preferredBottle ?? "a new bottle named \"games\"")).")
        }
        // Keep running badges current while the library is on screen.
        .task {
            while !Task.isCancelled {
                await store.refreshLibrary()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    @ViewBuilder private var steamButton: some View {
        // Prefer Steam in the default bottle; fall back to any bottle that has it.
        if let steam = store.launchers.first(where: { $0.integration == "steam" && $0.bottle == store.defaultBottle })
            ?? store.launchers.first(where: { $0.integration == "steam" }) {
            Button {
                Task { await store.quick("Opening Steam…", ["run", steam.bottle, steam.path]) }
            } label: { Label("Open Steam", systemImage: "cloud") }
            .help("Open the Steam client (bottle \(steam.bottle))")
        } else {
            Button { confirmSteam = true } label: { Label("Install Steam", systemImage: "icloud.and.arrow.down") }
                .disabled(store.runtimes.isEmpty)
        }
    }

    /// Into the default bottle; with no bottles yet, create "games" and make it the default.
    private func installSteam() async {
        var target = store.preferredBottle ?? "games"
        if store.bottles.isEmpty {
            target = "games"
            await store.perform("Creating bottle \"games\" (first boot takes a minute)…", ["bottle", "create", target, "--default"])
        }
        await store.perform("Installing Steam…", ["install", target, "steam"])
    }
}

struct GameCard: View {
    @Environment(Store.self) private var store
    let game: Game
    var openBottle: (String) -> Void
    @State private var hovering = false
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                CoverImage(path: game.image, title: game.name)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(hovering ? 0.35 : 0.15), radius: hovering ? 10 : 4, y: 3)
                if game.running || hovering {
                    actionButton.padding(.bottom, 12).transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if game.running {
                    Label("Running", systemImage: "circle.fill")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.green.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name).font(.headline).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { Task { await store.play(game) } }
        .contextMenu {
            if game.running {
                Button("Stop") { Task { await store.stop(game) } }
            } else {
                Button("Play") { Task { await store.play(game) } }
            }
            Divider()
            if game.isManual && !game.running {
                Button("Run as Administrator") {
                    Task { await store.quick("Starting \(game.name) as administrator…", ["run", "--admin", game.bottle, game.name]) }
                }
            }
            Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: game.folder)) }
            Button("Bottle Settings") { openBottle(game.bottle) }
            if game.isManual {
                Divider()
                Button("Remove from Library…", role: .destructive) { confirmRemove = true }
            }
        }
        .confirmationDialog("Remove \(game.name) from the library?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) {
                Task { await store.quick("Removing…", ["library", "remove", game.bottle, game.key]) }
            }
        } message: {
            Text("Only the library entry is removed. The game's files stay where they are.")
        }
    }

    private var subtitle: String {
        let source = game.isManual ? "Added by you" : game.source.capitalized
        return store.bottles.count > 1 ? "\(source) · \(game.bottle)" : source
    }

    @ViewBuilder private var actionButton: some View {
        if game.running {
            Button { Task { await store.stop(game) } } label: { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(.borderedProminent).tint(.red)
        } else {
            Button { Task { await store.play(game) } } label: { Label("Play", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}

/// Store artwork when there is some, otherwise a generated tile with the game's initials.
struct CoverImage: View {
    let path: String
    let title: String
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [hue.opacity(0.85), hue.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(initials).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
            }
        }
        .task(id: path) { image = path.isEmpty ? nil : NSImage(contentsOfFile: path) }
    }

    private var initials: String {
        title.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private var hue: Color {
        let h = Double(abs(title.hashValue % 360)) / 360
        return Color(hue: h, saturation: 0.55, brightness: 0.6)
    }
}

// MARK: - Add a non-store game

struct AddGameSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable { case game = "It's the game", installer = "It's an installer" }
    enum Step { case pick, details, installing }

    @State private var step: Step = .pick
    @State private var file: URL?
    @State private var name = ""
    @State private var kind: Kind = .game
    @State private var bottle = ""
    @State private var picking = false
    @State private var found: [String] = []
    @State private var selected: Set<String> = []
    @State private var scanned = false
    @State private var installStarted: Date?
    @State private var asAdmin = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a Windows Game").font(.title2.bold())
            switch step {
            case .pick: pickStep
            case .details: detailsStep
            case .installing: installingStep
            }
        }
        .padding(24)
        .frame(width: 520)
        .fileImporter(isPresented: $picking, allowedContentTypes: [
            UTType(filenameExtension: "exe") ?? .item, UTType(filenameExtension: "msi") ?? .item,
            UTType(filenameExtension: "bat") ?? .item,
        ]) { result in
            guard case .success(let url) = result else { return }
            choose(url)
        }
        .onAppear { bottle = defaultBottle }
    }

    private var pickStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose the game's .exe, or the installer you downloaded (setup.exe, .msi).")
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Choose File…") { picking = true }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                LabeledContent("File", value: file?.lastPathComponent ?? "")
                Picker("This file", selection: $kind) { ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                if kind == .game {
                    TextField("Name", text: $name)
                }
                Picker("Bottle", selection: $bottle) {
                    ForEach(store.bottles) { Text($0.name).tag($0.name) }
                    if store.bottles.isEmpty { Text("New bottle \"games\"").tag("games") }
                }
                if kind == .installer {
                    Toggle("Run as administrator", isOn: $asAdmin)
                        .help("Copies the installer into the bottle first, fixes read-only files, and grants Wine's full admin token. Fixes most \"access denied\" errors.")
                }
            }
            .formStyle(.grouped)
            Text(kind == .game
                 ? "The game runs from where it is now. If you move or delete its folder, remove it here and add it again."
                 : "The installer opens next. Install to the suggested location (usually C:\\Program Files), then come back here.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Back") { step = .pick }
                Spacer()
                Button(kind == .game ? "Add to Library" : "Run Installer") { Task { await submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(kind == .game && name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var installingStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox { ActivityView(bottle: bottle).padding(4) }
            if !scanned {
                Text("Finish the installer, then look for the games it installed.").foregroundStyle(.secondary)
            } else if found.isEmpty {
                Text("No new programs found under Program Files. If the installer is still running, finish it and look again.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Choose which programs to add:").foregroundStyle(.secondary)
                List(found, id: \.self) { path in
                    Toggle(isOn: Binding(get: { selected.contains(path) },
                                         set: { if $0 { selected.insert(path) } else { selected.remove(path) } })) {
                        VStack(alignment: .leading) {
                            Text(displayName(path))
                            Text(path.components(separatedBy: "/drive_c/").last ?? path)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                .frame(height: 180)
            }
            HStack {
                Button("Done") { dismiss() }
                Spacer()
                Button(scanned ? "Look Again" : "Find Installed Games") { Task { await scan() } }
                if !selected.isEmpty {
                    Button("Add \(selected.count) to Library") { Task { await addSelected() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var defaultBottle: String {
        store.preferredBottle ?? "games"
    }

    private func choose(_ url: URL) {
        file = url
        let lower = url.lastPathComponent.lowercased()
        kind = (lower.hasSuffix(".msi") || ["setup", "install", "installer", "unins"].contains { lower.contains($0) }) ? .installer : .game
        name = displayName(url.path)
        step = .details
    }

    private func displayName(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
    }

    private func ensureBottle() async {
        if !store.bottles.contains(where: { $0.name == bottle }) {
            await store.perform("Creating bottle \"\(bottle)\" (first boot takes a minute)…", ["bottle", "create", bottle])
        }
    }

    private func submit() async {
        guard let file else { return }
        await ensureBottle()
        if kind == .game {
            await store.quick("Adding \(name)…", ["library", "add", bottle, name.trimmingCharacters(in: .whitespaces), file.path])
            dismiss()
        } else {
            installStarted = Date()
            await store.quick("Starting installer…", ["run"] + (asAdmin ? ["--admin"] : []) + [bottle, file.path])
            step = .installing
        }
    }

    private func scan() async {
        // Only folders the installer touched (a little slack for clock granularity).
        let since = installStarted.map { ["--since", String(Int($0.timeIntervalSince1970) - 5)] } ?? []
        let out = (try? await store.cli.run(["program", "scan", bottle] + since)) ?? ""
        let known = Set(store.games.map { $0.folder })
        found = out.split(separator: "\n").map(String.init)
            .filter { !known.contains(URL(fileURLWithPath: $0).deletingLastPathComponent().path) }
        selected = found.count == 1 ? Set(found) : []
        scanned = true
    }

    private func addSelected() async {
        for path in selected.sorted() {
            await store.quick("Adding \(displayName(path))…", ["library", "add", bottle, displayName(path), path])
        }
        dismiss()
    }
}

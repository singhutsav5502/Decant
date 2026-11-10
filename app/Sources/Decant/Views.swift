import SwiftUI
import UniformTypeIdentifiers

enum Route: Hashable {
    case library
    case bottle(String)
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @State private var route: Route? = .library
    @State private var showingNew = false
    @State private var showingSetup = false

    var body: some View {
        NavigationSplitView {
            List(selection: $route) {
                Label("Library", systemImage: "square.grid.2x2").tag(Route.library)
                Section("Bottles") {
                    ForEach(store.bottles) { b in
                        Label {
                            HStack {
                                Text(b.name)
                                if b.name == store.defaultBottle {
                                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                                        .help("Default bottle: new games and installers go here")
                                }
                            }
                        } icon: { Image(systemName: "wineglass") }
                        .tag(Route.bottle(b.name))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .toolbar {
                Button { showingNew = true } label: { Label("New Bottle", systemImage: "plus.rectangle.on.folder") }
                    .disabled(store.runtimes.isEmpty)
                    .help("New bottle")
            }
        } detail: {
            if store.runtimes.isEmpty {
                SetupView()
            } else {
                switch route {
                case .bottle(let name):
                    if let bottle = store.bottles.first(where: { $0.name == name }) {
                        BottleDetailView(bottle: bottle)
                    } else {
                        LibraryView { route = .bottle($0) }
                    }
                default:
                    LibraryView { route = .bottle($0) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .status) { StatusView() }
            ToolbarItem {
                Button { showingSetup = true } label: { Label("Components", systemImage: "shippingbox") }
                    .help("Wine runtimes and graphics backends")
            }
        }
        .sheet(isPresented: $showingNew) { NewBottleSheet { route = .bottle($0) } }
        .sheet(isPresented: $showingSetup) {
            VStack(spacing: 0) {
                SetupView()
                HStack { Spacer(); Button("Done") { showingSetup = false }.keyboardShortcut(.defaultAction) }.padding()
            }.frame(width: 540, height: 500)
        }
    }
}

struct StatusView: View {
    @Environment(Store.self) private var store
    var body: some View {
        if let busy = store.busy {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(busy) }
        } else if let err = store.lastError {
            Label(err.split(separator: "\n").last.map(String.init) ?? err, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red).lineLimit(1).help(err)
        } else if let msg = store.lastMessage {
            Text(msg).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

// MARK: - Bottle detail

struct BottleDetailView: View {
    @Environment(Store.self) private var store
    let bottle: Bottle
    @State private var importing = false
    @State private var importAsAdmin = false
    @State private var log = ""
    @State private var fixes: [FixState] = []

    var body: some View {
        Form {
            Section("Play") {
                ForEach(bottle.programs) { p in
                    HStack {
                        Label(p.label, systemImage: "gamecontroller")
                        Spacer()
                        Button("Play") { Task { await store.launch(bottle, p.label) } }
                            .buttonStyle(.borderedProminent)
                        Button { Task { await store.perform("Removing…", ["program", "remove", bottle.name, p.label]) } }
                            label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button("Run .exe / installer…") { importAsAdmin = false; importing = true }
                    Button("Run as Administrator…") { importAsAdmin = true; importing = true }
                        .help("Copies the installer into the bottle, fixes permissions and grants Wine's full admin token")
                    Button("Install Steam") { Task { await store.perform("Installing Steam…", ["install-steam", bottle.name]) } }
                    Spacer()
                    Button("Find installed games") { Task { await scanPrograms() } }
                }
            }

            Section("Graphics (DirectX → Metal)") {
                Picker("Backend", selection: binding("BACKEND", bottle.backend.rawValue)) {
                    ForEach(Backend.allCases) { b in
                        Text(b.title + note(b)).tag(b.rawValue)
                    }
                }
                Text(bottle.backend.blurb).font(.caption).foregroundStyle(.secondary)
                Toggle("MetalFX upscaling", isOn: flag("METALFX"))
                    .disabled(bottle.backend != .d3dmetal && bottle.backend != .dxmt && bottle.backend != .auto)
                Toggle("Metal performance HUD", isOn: flag("METAL_HUD"))
                Toggle("Retina resolution (sharper, slower)", isOn: flag("RETINA"))
            }

            Section("CPU & Wine") {
                Picker("Wine runtime", selection: binding("RUNTIME", bottle.runtime)) {
                    ForEach(store.runtimes, id: \.self) { Text($0).tag($0) }
                }
                Toggle("msync (Mach semaphores, CrossOver-patched Wine)", isOn: flag("MSYNC"))
                Toggle("Advertise AVX/AVX2 via Rosetta", isOn: flag("AVX"))
                Picker("Windows version", selection: binding("WINVER", bottle.values["WINVER"] ?? "win10")) {
                    ForEach(["win11", "win10", "win81", "win7", "winxp"], id: \.self) { Text($0).tag($0) }
                }
                TextField("Extra env (K=V K2=V2)", text: binding("EXTRA_ENV", bottle.values["EXTRA_ENV"] ?? ""))
            }

            Section {
                ForEach(fixes) { fix in
                    Toggle(isOn: Binding(get: { fix.enabled }, set: { on in
                        Task {
                            await store.perform(on ? "Enabling \(fix.id)…" : "Disabling \(fix.id)…",
                                                ["fix", on ? "enable" : "disable", bottle.name, fix.id])
                            fixes = await store.fixes(for: bottle)
                        }
                    })) {
                        VStack(alignment: .leading) {
                            Text(fix.title)
                            Text(fix.id).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if fixes.isEmpty { Text("No recipes installed.").foregroundStyle(.secondary) }
            } header: {
                Text("Compatibility fixes")
            } footer: {
                Text("Per-app recipes applied automatically when a matching program launches.")
            }

            Section("Activity") {
                ActivityView(bottle: bottle.name)
            }

            Section("Tools") {
                HStack {
                    Button("Open C: drive") { NSWorkspace.shared.open(bottle.driveC) }
                    Button("winecfg") { Task { await store.perform("Opening winecfg…", ["winecfg", bottle.name]) } }
                    Button("regedit") { Task { await store.perform("Opening regedit…", ["regedit", bottle.name]) } }
                    Button("Stop all") { Task { await store.perform("Stopping…", ["kill", bottle.name]) } }
                    if store.defaultBottle != bottle.name {
                        Button("Make Default Bottle") { Task { await store.makeDefault(bottle.name) } }
                            .help("New games, installers and Steam go to the default bottle")
                    }
                    Button("Game Controllers") { Task { await store.quick("Opening Game Controllers…", ["controllers", bottle.name]) } }
                        .help("Shows Wine's controller panel: press buttons to check a pad is detected")
                    Button("Repair Permissions") { Task { await store.repair(bottle.name) } }
                        .help("Fix \"access denied\" caused by read-only or wrongly-owned files in this bottle")
                    Spacer()
                    Button("Delete bottle", role: .destructive) {
                        Task { await store.perform("Deleting…", ["bottle", "delete", bottle.name]) }
                    }
                }
            }

            Section("Last run log") {
                ScrollView {
                    Text(log.isEmpty ? "No runs yet." : log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 140)
                Button("Reload log") { loadLog() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(bottle.name)
        .onAppear(perform: loadLog)
        .task(id: bottle.name) { fixes = await store.fixes(for: bottle) }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType(filenameExtension: "exe") ?? .item,
                                            UTType(filenameExtension: "msi") ?? .item, .item]) { result in
            guard case .success(let url) = result else { return }
            Task { await store.launch(bottle, url.path, admin: importAsAdmin) }
        }
    }

    private func installed(_ b: Backend) -> Bool {
        b == .auto || (store.backends.first(where: { $0.name == b.rawValue })?.installed ?? false)
    }

    private func note(_ b: Backend) -> String {
        if !installed(b) { return " — not installed" }
        if b == .dxmt && !store.dxmtRuntimes.contains(bottle.runtime) { return " — not supported by this Wine" }
        return ""
    }

    private func binding(_ key: String, _ current: String) -> Binding<String> {
        Binding(get: { current }, set: { v in Task { await store.set(bottle, key, v) } })
    }

    private func flag(_ key: String) -> Binding<Bool> {
        Binding(get: { bottle.flag(key) }, set: { v in Task { await store.set(bottle, key, v ? "1" : "0") } })
    }

    private func loadLog() {
        let text = (try? String(contentsOf: bottle.latestLog, encoding: .utf8)) ?? ""
        log = String(text.suffix(6000))
    }

    private func scanPrograms() async {
        let found = (try? await store.cli.run(["program", "scan", bottle.name])) ?? ""
        for path in found.split(separator: "\n") {
            let label = URL(fileURLWithPath: String(path)).deletingPathExtension().lastPathComponent
            await store.perform("Adding \(label)…", ["program", "add", bottle.name, label, String(path)])
        }
        if found.isEmpty { store.lastMessage = "No games found under Program Files" }
    }
}

// MARK: - New bottle

struct NewBottleSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onCreate: (String) -> Void
    @State private var name = ""
    @State private var backend: Backend?          // nil = let decant pick what this runtime supports
    @State private var runtime = ""

    var body: some View {
        Form {
            TextField("Name", text: $name, prompt: Text("e.g. steam"))
            Picker("Runtime", selection: $runtime) { ForEach(store.runtimes, id: \.self) { Text($0).tag($0) } }
            Picker("Graphics", selection: $backend) {
                Text("Automatic (best supported)").tag(Backend?.none)
                ForEach(Backend.allCases.filter { $0 != .auto }) { Text($0.title).tag(Backend?.some($0)) }
            }
            Text(backend?.blurb ?? Backend.auto.blurb)
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear { runtime = store.runtimes.first ?? "" }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    let n = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-")
                    dismiss()
                    Task {
                        await store.perform("Creating \(n)… (first boot takes a minute)",
                                            ["bottle", "create", n, "--runtime", runtime]
                                                + (backend.map { ["--backend", $0.rawValue] } ?? []))
                        onCreate(n)
                    }
                }.disabled(name.isEmpty || runtime.isEmpty)
            }
        }
    }
}

// MARK: - Components (runtimes + backends)

struct SetupView: View {
    @Environment(Store.self) private var store
    @State private var pickingGPTK = false

    var body: some View {
        Form {
            Section("System check") {
                Text(store.doctor.isEmpty ? "…" : store.doctor)
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            Section("Recommended setup") {
                Text("Installs whatever is missing: Wine, DXMT and DXVK, then creates the default bottle \"games\". Existing bottles aren't changed.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Set Up Recommended") { Task { await store.perform("Setting up (downloads can take a few minutes)…", ["setup"]) } }
                    .help("Runs `decant setup`. For DirectX 12, import D3DMetal below; for DXMT, build CrossOver Wine from a source checkout: decant setup --build-wine")
            }
            Section("Wine runtimes") {
                ForEach(store.runtimes, id: \.self) { Text($0) }
                HStack {
                    Button("Download Wine Staging") { Task { await store.perform("Downloading Wine (~220 MB)…", ["runtime", "install", "staging"]) } }
                    Button("Download Wine Devel") { Task { await store.perform("Downloading Wine (~220 MB)…", ["runtime", "install", "devel"]) } }
                }
            }
            Section("Graphics backends") {
                ForEach(store.backends.filter { $0.name != "wined3d" }) { c in
                    HStack {
                        Text(Backend(rawValue: c.name)?.title ?? c.name)
                        Spacer()
                        if c.installed { Text(c.detail).font(.caption).foregroundStyle(.secondary) }
                        else if c.name == "d3dmetal" { Button("Import from GPTK…") { pickingGPTK = true } }
                        else { Button("Install") { Task { await store.perform("Installing \(c.name)…", ["backend", "install", c.name]) } } }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $pickingGPTK, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            Task { await store.perform("Importing D3DMetal…", ["backend", "install", "d3dmetal", url.path]) }
        }
        .task { await store.refresh() }
    }
}

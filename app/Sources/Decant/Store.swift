import Foundation
import Observation

@MainActor @Observable
final class Store {
    let cli = CLI.locate()

    var bottles: [Bottle] = []
    var runtimes: [String] = []
    var dxmtRuntimes: Set<String> = []   // runtimes whose Wine can drive DXMT (docs/adr/0011)
    var backends: [Component] = []
    var doctor = ""
    var busy: String?          // non-nil while a long CLI action runs
    var lastError: String?
    var lastMessage: String?
    var games: [Game] = []
    var defaultBottle: String?          // `decant bottle default`: where new games/installers go
    var launchers: [Launcher] = []

    func refresh() async {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: CLI.home.appendingPathComponent("bottles").path)) ?? []
        bottles = names.sorted().compactMap(Bottle.load)
        let rt = ((try? await cli.run(["runtime", "list"])) ?? "").split(separator: "\n")
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        runtimes = rt.compactMap(\.first)
        dxmtRuntimes = Set(rt.filter { $0.count > 2 && $0[2] == "yes" }.map { $0[0] })
        backends = ((try? await cli.run(["backend", "list"])) ?? "")
            .split(separator: "\n").map { line in
                let f = line.split(separator: "\t").map(String.init)
                return Component(name: f[0], installed: f.count > 1 && f[1] == "installed", detail: f.count > 2 ? f[2] : "")
            }
        doctor = (try? await cli.run(["doctor"], allowFailure: true)) ?? ""
        let def = ((try? await cli.run(["bottle", "default"])) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        defaultBottle = def.isEmpty ? nil : def
        await refreshLibrary()
    }

    /// Cheap enough to poll: reads manifests and one `ps` snapshot.
    func refreshLibrary() async {
        let rows = ((try? await cli.run(["library"])) ?? "").split(separator: "\n")
        let fresh: [Game] = rows.compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 7 else { return nil }
            return Game(bottle: f[0], key: f[1], name: f[2], source: f[3], folder: f[4], image: f[5], running: f[6] == "1")
        }
        if fresh != games { games = fresh }
        let ls: [Launcher] = ((try? await cli.run(["integration", "list"])) ?? "").split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return f.count >= 4 ? Launcher(bottle: f[0], integration: f[1], title: f[2], path: f[3]) : nil
        }
        if ls != launchers { launchers = ls }
    }

    /// Fix bottle permissions. Read-only bits are fixed without a password; files owned by
    /// another user (left by running Wine with sudo) need one `chown`, which macOS's own
    /// administrator prompt runs. Returns false if the user cancelled the prompt.
    @discardableResult
    func repair(_ bottle: String) async -> Bool {
        let sudo = ((try? await cli.run(["repair", bottle, "--print-sudo"])) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !sudo.isEmpty {
            busy = "Waiting for administrator password…"
            let escaped = sudo.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = "do shell script \"\(escaped)\" with administrator privileges"
            let ok = await Self.osascript(script)
            busy = nil
            if !ok { lastError = "Permission repair cancelled"; return false }
        }
        await perform("Repairing permissions…", ["repair", bottle])
        return true
    }

    private nonisolated static func osascript(_ script: String) async -> Bool {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus == 0) }
            do { try p.run() } catch { cont.resume(returning: false) }
        }
    }

    /// The bottle to use when the user hasn't picked one: the default, else the first.
    var preferredBottle: String? { defaultBottle ?? bottles.first?.name }

    func makeDefault(_ bottle: String) async {
        await perform("Setting default bottle…", ["bottle", "default", bottle])
    }

    func play(_ game: Game) async {
        await quick("Starting \(game.name)…", ["play", game.bottle, game.key])
    }

    func stop(_ game: Game) async {
        await quick("Stopping \(game.name)…", ["stop", game.bottle, game.key])
    }

    /// Like perform, but only reloads the library (launches shouldn't block on a full refresh).
    func quick(_ label: String, _ args: [String]) async {
        busy = label
        lastError = nil
        do {
            let out = try await cli.run(args)
            lastMessage = out.split(separator: "\n").last.map(String.init)
        } catch {
            lastError = error.localizedDescription
        }
        busy = nil
        try? await Task.sleep(for: .seconds(2))
        await refreshLibrary()
    }

    /// Run a CLI action, surfacing progress and errors, then reload state.
    func perform(_ label: String, _ args: [String]) async {
        busy = label
        lastError = nil
        defer { busy = nil }
        do {
            let out = try await cli.run(args)
            lastMessage = out.split(separator: "\n").last.map(String.init)
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }

    func set(_ bottle: Bottle, _ key: String, _ value: String) async {
        await perform("Updating \(bottle.name)…", ["bottle", "set", bottle.name, "\(key)=\(value)"])
    }

    func fixes(for bottle: Bottle) async -> [FixState] {
        let out = (try? await cli.run(["fix", "status", bottle.name])) ?? ""
        return out.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return f.count >= 3 ? FixState(id: f[0], enabled: f[1] == "enabled", title: f[2]) : nil
        }
    }

    func launch(_ bottle: Bottle, _ target: String, admin: Bool = false) async {
        do {
            lastMessage = try await cli.run(["run"] + (admin ? ["--admin"] : []) + [bottle.name, target])
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

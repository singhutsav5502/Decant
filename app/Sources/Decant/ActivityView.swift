import SwiftUI

/// Parsed `decant status <bottle> --tsv`.
struct BottleStatus: Equatable, Sendable {
    struct Proc: Identifiable, Equatable, Sendable {
        var pid: String
        var cpu: Double
        var elapsed: String
        var name: String
        var isWine: Bool          // Wine's own background services
        var id: String { pid }
    }
    var state = "stopped"        // busy | waiting | stopped
    var message = ""
    var procs: [Proc] = []
    var launchLog = ""
    var launchLogAge: Int?
    var installerLog = ""
    var installerLogAge: Int?

    init() {}

    init(tsv: String) {
        for line in tsv.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            switch f.first {
            case "proc" where f.count >= 6:
                procs.append(Proc(pid: f[1], cpu: Double(f[2]) ?? 0, elapsed: f[3], name: f[4], isWine: f[5] == "1"))
            case "log" where f.count >= 3: launchLog = f[1]; launchLogAge = Int(f[2])
            case "installer-log" where f.count >= 3: installerLog = f[1]; installerLogAge = Int(f[2])
            case "state" where f.count >= 3: state = f[1]; message = f[2]
            default: break
            }
        }
    }
}

/// Live "is it working or stuck?" panel for one bottle, with log and diagnostics actions.
struct ActivityView: View {
    @Environment(Store.self) private var store
    let bottle: String
    @State private var status = BottleStatus()
    @State private var showWine = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(headline).font(.headline)
                Spacer()
                if status.state != "stopped" {
                    Toggle("Wine processes", isOn: $showWine).toggleStyle(.checkbox).font(.caption)
                }
            }
            if !status.message.isEmpty && status.state != "stopped" {
                Text(status.message).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(status.procs.filter { showWine || !$0.isWine }) { p in
                HStack {
                    Text(p.name).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f%% CPU", p.cpu)).monospacedDigit()
                        .foregroundStyle(p.cpu >= 5 ? .primary : .secondary)
                    Text(p.elapsed).monospacedDigit().foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                }
                .font(.callout)
            }
            HStack(spacing: 14) {
                if let age = status.launchLogAge { Text("Launch log: \(ago(age))") }
                if let age = status.installerLogAge { Text("Installer log: \(ago(age))") }
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Open Launch Log") { open(status.launchLog) }.disabled(status.launchLog.isEmpty)
                if !status.installerLog.isEmpty {
                    Button("Open Installer Log") { open(status.installerLog) }
                }
                Button("Show Logs in Finder") {
                    NSWorkspace.shared.open(CLI.home.appendingPathComponent("bottles/\(bottle)/logs"))
                }
                Spacer()
                Button("Export Diagnostics…") { Task { await exportDiagnostics() } }
                    .help("Zip the logs, bottle settings and current activity to your Desktop, to attach to a bug report")
            }
        }
        .task(id: bottle) {
            while !Task.isCancelled {
                let tsv = (try? await store.cli.run(["status", bottle, "--tsv"])) ?? ""
                let fresh = BottleStatus(tsv: tsv)
                if fresh != status { status = fresh }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var color: Color {
        switch status.state {
        case "busy": .green
        case "waiting": .orange
        default: .secondary
        }
    }

    private var headline: String {
        switch status.state {
        case "busy": "Working"
        case "waiting": "Waiting for you"
        default: "Nothing running"
        }
    }

    private func ago(_ s: Int) -> String {
        s < 60 ? "updated \(s)s ago" : s < 3600 ? "updated \(s / 60) min ago" : "updated \(s / 3600) h ago"
    }

    private func open(_ path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))   // .log opens in Console
    }

    private func exportDiagnostics() async {
        store.busy = "Collecting diagnostics…"
        let out = (try? await store.cli.run(["diagnostics", bottle])) ?? ""
        store.busy = nil
        if let zip = out.split(separator: "\n").last.map(String.init), zip.hasSuffix(".zip") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: zip)])
            store.lastMessage = "Diagnostics saved to \(URL(fileURLWithPath: zip).lastPathComponent)"
        } else {
            store.lastError = "Couldn't create diagnostics"
        }
    }
}

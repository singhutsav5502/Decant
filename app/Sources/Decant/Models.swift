import Foundation

enum Backend: String, CaseIterable, Identifiable, Sendable {
    case auto, dxmt, d3dmetal, dxvk, wined3d
    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Automatic"
        case .dxmt: "DXMT"
        case .d3dmetal: "D3DMetal (GPTK)"
        case .dxvk: "DXVK + MoltenVK"
        case .wined3d: "WineD3D (OpenGL)"
        }
    }

    var blurb: String {
        switch self {
        case .auto: "Best layer per API at every launch: D3DMetal (or DXMT) for DX10–12, WineD3D for DX9 and older, MoltenVK for Vulkan."
        case .dxmt: "DirectX 10/11 straight to Metal. Fastest open-source path for most DX11 games."
        case .d3dmetal: "Apple's DirectX 11/12 → Metal layer. Best for DX12. Needs your own Game Porting Toolkit."
        case .dxvk: "DirectX 9–11 via Vulkan on MoltenVK. Good for DX9 titles; no geometry shaders."
        case .wined3d: "Wine's built-in OpenGL renderer. Slow; fallback for very old games."
        }
    }
}

struct Program: Identifiable, Hashable, Sendable {
    var label: String
    var path: String
    var id: String { label }
}

/// Mirror of bottles/<name>/bottle.conf (KEY=VALUE lines).
struct Bottle: Identifiable, Hashable, Sendable {
    var name: String
    var values: [String: String]
    var programs: [Program]
    var id: String { name }

    var dir: URL { CLI.home.appendingPathComponent("bottles/\(name)") }
    var driveC: URL { dir.appendingPathComponent("prefix/drive_c") }
    var latestLog: URL { dir.appendingPathComponent("logs/latest.log") }

    var backend: Backend { Backend(rawValue: values["BACKEND"] ?? "") ?? .wined3d }
    var runtime: String { values["RUNTIME"] ?? "" }
    func flag(_ key: String) -> Bool { values[key] == "1" }

    static func load(name: String) -> Bottle? {
        let dir = CLI.home.appendingPathComponent("bottles/\(name)")
        guard let conf = try? String(contentsOf: dir.appendingPathComponent("bottle.conf"), encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in conf.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            values[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        let tsv = (try? String(contentsOf: dir.appendingPathComponent("programs.tsv"), encoding: .utf8)) ?? ""
        let programs = tsv.split(separator: "\n").compactMap { line -> Program? in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            return parts.count >= 2 ? Program(label: String(parts[0]), path: String(parts[1])) : nil
        }
        return Bottle(name: values["NAME"] ?? name, values: values, programs: programs)
    }
}

/// One row of `decant fix status <bottle>`: a compatibility recipe and whether it's on.
struct FixState: Identifiable, Hashable, Sendable {
    var id: String
    var enabled: Bool
    var title: String
}

/// One row of `decant library`: a game from a store integration or added by hand.
struct Game: Identifiable, Hashable, Sendable {
    var bottle: String
    var key: String          // "<source>:<id>", e.g. steam:2784470, manual:My Game
    var name: String
    var source: String       // integration id ("steam") or "manual"
    var folder: String
    var image: String
    var running: Bool
    var id: String { bottle + "\u{1F}" + key }
    var isManual: Bool { source == "manual" }
}

/// One row of `decant integration list`: a store launcher installed in a bottle.
struct Launcher: Identifiable, Hashable, Sendable {
    var bottle: String
    var integration: String
    var title: String
    var path: String         // Windows path of the launcher exe
    var id: String { bottle + "/" + integration }
}

struct Component: Identifiable, Sendable {
    var name: String
    var installed: Bool
    var detail: String
    var id: String { name }
}

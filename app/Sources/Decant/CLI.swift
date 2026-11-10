import Foundation

/// Thin async wrapper around the `decant` shell CLI, which owns all real logic.
struct CLI: Sendable {
    struct Failure: LocalizedError {
        let output: String
        var errorDescription: String? { output.isEmpty ? "decant failed" : output }
    }

    let path: String

    /// Bundled copy inside Decant.app, else $DECANT_CLI, else ../bin/decant next to the package (dev runs).
    static func locate() -> CLI {
        if let bundled = Bundle.main.path(forResource: "decant", ofType: nil) {
            return CLI(path: bundled)
        }
        if let env = ProcessInfo.processInfo.environment["DECANT_CLI"] {
            return CLI(path: env)
        }
        #if DEBUG
        // Dev runs only: #filePath embeds the builder's source path, so release builds must not use it.
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("bin/decant").path
        return CLI(path: dev)
        #else
        return CLI(path: "decant")  // a release app always bundles the CLI; this only fails loudly
        #endif
    }

    static var home: URL {
        if let h = ProcessInfo.processInfo.environment["DECANT_HOME"] { return URL(fileURLWithPath: h) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Decant")
    }

    @discardableResult
    func run(_ args: [String], allowFailure: Bool = false) async throws -> String {
        let path = self.path
        return try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [path] + args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            p.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if proc.terminationStatus == 0 || allowFailure { cont.resume(returning: out) }
                else { cont.resume(throwing: Failure(output: out)) }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}

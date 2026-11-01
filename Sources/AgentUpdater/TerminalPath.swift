import Foundation

/// Whether a new Terminal window can find commands in ~/.local/bin, and the one-line fix when it
/// can't. macOS doesn't put that folder on PATH by default.
enum TerminalPath {
    static var binDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
    }

    /// The user's login shell. The SHELL variable is often missing for apps opened from Finder.
    static var shell: String {
        if let entry = getpwuid(getuid()), let raw = entry.pointee.pw_shell {
            let path = String(cString: raw)
            if !path.isEmpty { return path }
        }
        return "/bin/zsh"
    }

    static var shellName: String { URL(fileURLWithPath: shell).lastPathComponent }

    /// The startup file the fix goes in, for the shells where that's unambiguous. zsh reads
    /// .zshrc from ZDOTDIR when the user sets one.
    static func startupFile(shell name: String = shellName, zdotdir: String? = nil,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        switch name {
        case "zsh":
            if let zdotdir, !zdotdir.isEmpty { URL(fileURLWithPath: zdotdir).appendingPathComponent(".zshrc") }
            else { home.appendingPathComponent(".zshrc") }
        case "bash": home.appendingPathComponent(".bash_profile")
        default: nil
        }
    }

    /// The line that puts ~/.local/bin on PATH, in the shell's own syntax.
    static func fixLine(shell name: String = shellName) -> String {
        name == "fish" ? "fish_add_path ~/.local/bin" : #"export PATH="$HOME/.local/bin:$PATH""#
    }

    /// What a new Terminal window gets: its PATH, and ZDOTDIR (where zsh keeps its startup files).
    struct Snapshot: Sendable {
        let path: String
        let zdotdir: String?
    }

    /// Asks an interactive login shell, started from the system's base PATH so the app's own
    /// environment can't hide a missing entry. nil if the shell fails or takes longer than five
    /// seconds.
    static func read(shell: String = shell, environment extra: [String: String] = [:]) async -> Snapshot? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: readNow(shell: shell, extra: extra))
            }
        }
    }

    private static let marker = "__AGENT_UPDATER_PATH__"

    private static func readNow(shell: String, extra: [String: String]) -> Snapshot? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-i", "-l", "-c",
                             "printf '%s%s%s%s%s' \(marker) \"$PATH\" \(marker) \"$ZDOTDIR\" \(marker)"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        env["TERM"] = "dumb"
        env.merge(extra) { $1 }
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        // Stop at the last marker, not at end of file: a startup file can leave a background
        // process holding the pipe open.
        let output = Output()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil }
            output.add(chunk)
        }
        do { try process.run() } catch { return nil }
        let finished = output.done.wait(timeout: .now() + 5) == .success
        pipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        guard finished else { return nil }
        let parts = output.text.components(separatedBy: marker)
        guard parts.count >= 4 else { return nil }
        return Snapshot(path: parts[1], zdotdir: parts[2].isEmpty ? nil : parts[2])
    }

    private final class Output: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var data = Data()
        private var signaled = false

        var text: String {
            lock.lock(); defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }

        func add(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(chunk)
            let complete = chunk.isEmpty
                || String(decoding: data, as: UTF8.self).components(separatedBy: marker).count >= 4
            if complete, !signaled {
                signaled = true
                done.signal()
            }
        }
    }

    /// Whether a PATH value includes `directory`, allowing for ~, trailing slashes and symlinks.
    static func path(_ path: String, contains directory: URL) -> Bool {
        let target = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.split(separator: ":").contains { entry in
            var dir = String(entry)
            if dir == "~" || dir.hasPrefix("~/") { dir = home + dir.dropFirst() }
            return URL(fileURLWithPath: dir).resolvingSymlinksInPath().standardizedFileURL.path == target
        }
    }

    /// Appends the fix to a startup file, creating the file if needed. Writes in place, so a
    /// symlinked dotfile stays a symlink. Does nothing if the line is already there.
    static func addFix(to file: URL, line: String = fixLine()) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: file.path) {
            guard fm.createFile(atPath: file.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
            }
        }
        let handle = try FileHandle(forUpdating: file)
        defer { try? handle.close() }
        let existing = String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
        if existing.components(separatedBy: "\n").contains(line) { return }
        let lead = existing.isEmpty ? "" : existing.hasSuffix("\n") ? "\n" : "\n\n"
        let block = lead + "# Added by Agent Updater so Terminal can find update-agents\n" + line + "\n"
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(block.utf8))
    }
}

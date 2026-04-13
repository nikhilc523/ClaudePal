import Foundation

// MARK: - Active Session Info

public struct ActiveSessionInfo: Equatable, Sendable {
    public let sessionId: String
    public let pid: Int
    public let cwd: String
    public let jsonlPath: String
    public let startedAt: Date

    public init(sessionId: String, pid: Int, cwd: String, jsonlPath: String, startedAt: Date) {
        self.sessionId = sessionId
        self.pid = pid
        self.cwd = cwd
        self.jsonlPath = jsonlPath
        self.startedAt = startedAt
    }
}

// MARK: - Session File Watcher

/// Watches Claude Code session files for active sessions and JSONL changes.
/// Uses DispatchSource for efficient filesystem monitoring (no polling).
public final class SessionFileWatcher: @unchecked Sendable {

    private let sessionsDir: String
    private let projectsDir: String

    private var dirSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private var fileFD: Int32 = -1

    private var watchedJSONLPath: String?
    private let queue = DispatchQueue(label: "com.claudepal.session-watcher", qos: .utility)

    /// Called when model info updates from the active session's JSONL.
    public var onModelInfoChanged: ((ModelInfo?) -> Void)?

    /// Called when active sessions list changes.
    public var onActiveSessionsChanged: (([ActiveSessionInfo]) -> Void)?

    public init(
        sessionsDir: String = NSHomeDirectory() + "/.claude/sessions",
        projectsDir: String = NSHomeDirectory() + "/.claude/projects"
    ) {
        self.sessionsDir = sessionsDir
        self.projectsDir = projectsDir
    }

    deinit {
        stop()
    }

    // MARK: - Start / Stop

    public func start() {
        // Initial scan
        queue.async { [weak self] in
            self?.scanSessions()
        }

        // Watch sessions directory for changes
        watchDirectory()
    }

    public func stop() {
        dirSource?.cancel()
        dirSource = nil
        fileSource?.cancel()
        fileSource = nil
        if dirFD >= 0 { close(dirFD); dirFD = -1 }
        if fileFD >= 0 { close(fileFD); fileFD = -1 }
        watchedJSONLPath = nil
    }

    /// Force a re-scan (useful when hooks arrive with session info).
    public func rescan() {
        queue.async { [weak self] in
            self?.scanSessions()
        }
    }

    // MARK: - Directory Watching

    private func watchDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: sessionsDir) {
            try? fm.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
        }

        dirFD = open(sessionsDir, O_EVTONLY)
        guard dirFD >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: [.write, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.scanSessions()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.dirFD, fd >= 0 {
                close(fd)
                self?.dirFD = -1
            }
        }

        dirSource = source
        source.resume()
    }

    // MARK: - Session Scanning

    private func scanSessions() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else { return }

        var activeSessions: [ActiveSessionInfo] = []

        for file in files where file.hasSuffix(".json") {
            let path = (sessionsDir as NSString).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = json["pid"] as? Int,
                  let sessionId = json["sessionId"] as? String,
                  let cwd = json["cwd"] as? String
            else { continue }

            // Check if PID is still alive
            guard kill(Int32(pid), 0) == 0 else { continue }

            let startedAtMs = json["startedAt"] as? Double ?? Date().timeIntervalSince1970 * 1000
            let startedAt = Date(timeIntervalSince1970: startedAtMs / 1000)

            // Resolve JSONL path
            let cwdEncoded = cwd.replacingOccurrences(of: "/", with: "-")
            let jsonlPath = (projectsDir as NSString)
                .appendingPathComponent(cwdEncoded)
                .appending("/\(sessionId).jsonl")

            guard fm.fileExists(atPath: jsonlPath) else { continue }

            activeSessions.append(ActiveSessionInfo(
                sessionId: sessionId,
                pid: pid,
                cwd: cwd,
                jsonlPath: jsonlPath,
                startedAt: startedAt
            ))
        }

        // Sort by most recently started
        activeSessions.sort { $0.startedAt > $1.startedAt }

        onActiveSessionsChanged?(activeSessions)

        // Watch the most recent session's JSONL
        if let primary = activeSessions.first {
            watchJSONL(at: primary.jsonlPath)
        }
    }

    // MARK: - JSONL File Watching

    private func watchJSONL(at path: String) {
        if watchedJSONLPath == path { return }

        // Clean up previous watcher
        fileSource?.cancel()
        fileSource = nil
        if fileFD >= 0 { close(fileFD); fileFD = -1 }

        watchedJSONLPath = path

        // Parse current state
        parseAndNotify(path: path)

        // Watch for writes
        fileFD = open(path, O_EVTONLY)
        guard fileFD >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileFD,
            eventMask: .write,
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.parseAndNotify(path: path)
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileFD, fd >= 0 {
                close(fd)
                self?.fileFD = -1
            }
        }

        fileSource = source
        source.resume()
    }

    private func parseAndNotify(path: String) {
        let url = URL(fileURLWithPath: path)
        let modelInfo = JSONLParser.parseLastAssistantMessage(from: url)
        onModelInfoChanged?(modelInfo)
    }
}

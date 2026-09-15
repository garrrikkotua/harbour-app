import Foundation
import HarbourCore

enum HarbourError: LocalizedError {
    case missingDaemonBinary
    case installCancelled
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDaemonBinary: return "harbour-daemon binary missing from app bundle"
        case .installCancelled: return "Admin authorization cancelled"
        case .installFailed(let s): return "Install failed: \(s)"
        }
    }
}

enum HelperInstaller {
    static let daemonPath = "/Library/PrivilegedHelperTools/com.harbour.daemon"
    static let stateDir = "/var/db/harbour"
    static let stateFile = "/var/db/harbour/state.json"
    static let plistPath = "/Library/LaunchDaemons/com.harbour.daemon.plist"
    static let label = "com.harbour.daemon"

    static func installAndStart(state: BlockState) throws {
        guard let bundled = Bundle.main.url(forResource: "harbour-daemon", withExtension: nil) else {
            throw HarbourError.missingDaemonBinary
        }

        let stateData = try JSONEncoder().encode(state)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let tempState = tempDir.appendingPathComponent("state.json")
        try stateData.write(to: tempState)

        let tempPlist = tempDir.appendingPathComponent("com.harbour.daemon.plist")
        try plistContents().write(to: tempPlist, atomically: true, encoding: .utf8)

        // Sequence matters:
        //   1. Serialize installation and reject an existing active job.
        //   2. Bootout any previous daemon and WAIT for it to exit — otherwise
        //      the old daemon could race us and delete the state.json we're
        //      about to write (expired-timer cleanup path).
        //   3. Install binary, plist, and state only after the old daemon is gone.
        //   4. Bootstrap. If this fails, `trap` removes state.json so the GUI
        //      doesn't flip into "active" with no enforcer running.
        let script = """
        #!/bin/bash
        set -eu
        export PATH=/usr/bin:/bin:/usr/sbin:/sbin
        # Serialize installers from multiple app windows/users.
        mkdir /var/run/com.harbour.install.lock || { echo "Another installation is in progress" >&2; exit 1; }
        trap 'rmdir /var/run/com.harbour.install.lock' EXIT
        if /bin/launchctl print system/\(label) >/dev/null 2>&1 && [ -f '\(stateFile)' ]; then
          echo "A block is already running. Wait for it to finish." >&2
          exit 1
        fi
        # Keep the root helper outside user-writable Homebrew directories.
        install -d -m 755 -o root -g wheel /Library/PrivilegedHelperTools
        install -d -m 755 -o root -g wheel '\(stateDir)'
        # Bootout any previous daemon and wait until its process is gone — launchctl
        # bootout returns when the job is removed, but the process can still be
        # running cleanup. Poll until the pidfile/PID is really dead before we
        # write new state.
        /bin/launchctl bootout system/\(label) 2>/dev/null || true
        for i in 1 2 3 4 5 6 7 8 9 10; do
          if ! pgrep -xf '\(daemonPath)' >/dev/null 2>&1; then break; fi
          sleep 0.5
        done
        if pgrep -xf '\(daemonPath)' >/dev/null 2>&1; then
          echo "Previous helper has not exited. Please retry." >&2
          exit 1
        fi
        install -m 755 -o root -g wheel \(shellQuote(bundled.path)) '\(daemonPath)'
        install -m 644 -o root -g wheel \(shellQuote(tempPlist.path)) '\(plistPath)'
        trap 'rm -f \(stateFile); rmdir /var/run/com.harbour.install.lock' EXIT
        install -m 644 -o root -g wheel \(shellQuote(tempState.path)) '\(stateFile)'
        /bin/launchctl bootstrap system '\(plistPath)'
        rmdir /var/run/com.harbour.install.lock
        trap - EXIT
        """

        try runAsAdmin(script: script)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func plistContents() -> String {
        // KeepAlive with SuccessfulExit=false means: respawn only on crash or
        // manual kill, NOT on a clean exit. Combined with the daemon's
        // `quickExitNoOp` path when state is missing, this prevents the
        // 1-Hz restart loop if bootout races with startup.
        //
        // ThrottleInterval caps respawn rate at 1 per 10s as a further backstop.
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(daemonPath)</string>
            </array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key><false/>
            </dict>
            <key>ThrottleInterval</key><integer>10</integer>
            <key>StandardOutPath</key><string>/var/log/harbour-daemon.log</string>
            <key>StandardErrorPath</key><string>/var/log/harbour-daemon.log</string>
        </dict>
        </plist>
        """
    }

    private static func runAsAdmin(script: String) throws {
        // Pass the script directly to osascript, avoiding a mutable on-disk
        // shell script and escaping AppleScript independently of shell quoting.
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let osa = "do shell script \"" + escaped + "\" with administrator privileges"
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", osa]
        let errPipe = Pipe()
        task.standardError = errPipe
        try task.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            if errStr.contains("-128") || errStr.contains("User cancel") {
                throw HarbourError.installCancelled
            }
            throw HarbourError.installFailed(errStr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

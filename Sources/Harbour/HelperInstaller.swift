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
    static let daemonPath = "/usr/local/bin/harbour-daemon"
    static let stateDir = "/var/db/harbour"
    static let stateFile = "/var/db/harbour/state.json"
    static let plistPath = "/Library/LaunchDaemons/com.harbour.daemon.plist"
    static let label = "com.harbour.daemon"

    static func installAndStart(state: BlockState) throws {
        guard let bundled = Bundle.main.url(forResource: "harbour-daemon", withExtension: nil) else {
            throw HarbourError.missingDaemonBinary
        }

        let stateData = try JSONEncoder().encode(state)
        let tempDir = FileManager.default.temporaryDirectory
        let tempState = tempDir.appendingPathComponent("cage-state.json")
        try stateData.write(to: tempState)

        let tempPlist = tempDir.appendingPathComponent("com.harbour.daemon.plist")
        try plistContents().write(to: tempPlist, atomically: true, encoding: .utf8)

        // Sequence matters:
        //   1. Install binary + plist (idempotent, no side-effects).
        //   2. Bootout any previous daemon and WAIT for it to exit — otherwise
        //      the old daemon could race us and delete the state.json we're
        //      about to write (expired-timer cleanup path).
        //   3. Write state.json only after old daemon is gone.
        //   4. Bootstrap. If this fails, `trap` removes state.json so the GUI
        //      doesn't flip into "active" with no enforcer running.
        let script = """
        #!/bin/bash
        set -e
        # Clean Macs may not have /usr/local/bin yet. Create it before copying.
        mkdir -p /usr/local/bin
        mkdir -p '\(stateDir)'
        install -m 755 -o root -g wheel '\(bundled.path)' '\(daemonPath)'
        install -m 644 -o root -g wheel '\(tempPlist.path)' '\(plistPath)'
        # Bootout any previous daemon and wait until its process is gone — launchctl
        # bootout returns when the job is removed, but the process can still be
        # running cleanup. Poll until the pidfile/PID is really dead before we
        # write new state.
        /bin/launchctl bootout system/\(label) 2>/dev/null || true
        for i in 1 2 3 4 5 6 7 8 9 10; do
          if ! pgrep -xf '\(daemonPath)' >/dev/null 2>&1; then break; fi
          sleep 0.5
        done
        trap 'rm -f \(stateFile)' EXIT
        install -m 644 -o root -g wheel '\(tempState.path)' '\(stateFile)'
        /bin/launchctl bootstrap system '\(plistPath)'
        trap - EXIT
        """

        let tempScript = tempDir.appendingPathComponent("cage-install.sh")
        try script.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)

        try runAsAdmin(path: tempScript.path)
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

    private static func runAsAdmin(path: String) throws {
        let osa = """
        do shell script "bash '\(path)'" with administrator privileges
        """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", osa]
        let errPipe = Pipe()
        task.standardError = errPipe
        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            if errStr.contains("-128") || errStr.contains("User cancel") {
                throw HarbourError.installCancelled
            }
            throw HarbourError.installFailed(errStr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

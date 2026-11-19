import Foundation

public struct BlockedApp: Codable, Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let bundleID: String

    public init(name: String, path: String, bundleID: String) {
        self.name = name
        self.path = path
        self.bundleID = bundleID
    }

    // Equatable / Hashable on `path` only — same rule as `id`. Two records
    // with different display names but the same bundle path refer to the
    // same app for dedup purposes.
    public static func == (lhs: BlockedApp, rhs: BlockedApp) -> Bool {
        lhs.path == rhs.path
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

public struct BlockConfig: Codable {
    public var domains: [String]
    public var apps: [BlockedApp]
    public var durationMinutes: Int

    public init(domains: [String] = [], apps: [BlockedApp] = [], durationMinutes: Int = 60) {
        self.domains = domains
        self.apps = apps
        self.durationMinutes = durationMinutes
    }
}

public struct BlockState: Codable {
    public let startTime: Date
    public let endTime: Date
    public let domains: [String]
    public let blockedPaths: [String]
    public let blockedBundleIDs: [String]
    /// Absolute path to the user-writable additions file the GUI appends to.
    /// Optional for backwards compat — if nil, the daemon skips polling for additions.
    public var additionsPath: String?
    /// UID of the account that started the block. Its attempt history is
    /// kept in its own file, readable only by that account. Optional for
    /// states written by older builds.
    public var ownerUID: UInt32?
    /// That account's UUID when the block started; a resumed daemon checks
    /// the UID still maps to it before attributing anything.
    public var ownerUUID: String?

    public init(
        startTime: Date,
        endTime: Date,
        domains: [String],
        blockedPaths: [String],
        blockedBundleIDs: [String],
        additionsPath: String? = nil,
        ownerUID: UInt32? = nil,
        ownerUUID: String? = nil
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.domains = domains
        self.blockedPaths = blockedPaths
        self.blockedBundleIDs = blockedBundleIDs
        self.additionsPath = additionsPath
        self.ownerUID = ownerUID
        self.ownerUUID = ownerUUID
    }
}

/// Additions made during an active block. Users can only grow the blocklist,
/// never shrink it — so this file is strictly accumulative until the block ends.
public struct BlockAdditions: Codable {
    public var domains: [String]
    public var apps: [BlockedApp]

    public init(domains: [String] = [], apps: [BlockedApp] = []) {
        self.domains = domains
        self.apps = apps
    }
}

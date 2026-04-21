import Foundation

struct BlockedApp: Codable, Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let bundleID: String
}

struct BlockConfig: Codable {
    var domains: [String] = []
    var apps: [BlockedApp] = []
    var durationMinutes: Int = 60
}

struct BlockState: Codable {
    let startTime: Date
    let endTime: Date
    let domains: [String]
    let blockedPaths: [String]
    let blockedBundleIDs: [String]
    /// Absolute path to the user-writable additions file the GUI appends to.
    /// Optional for backwards compat — if nil, the daemon skips polling for additions.
    var additionsPath: String? = nil
}

/// Additions made during an active block. Users can only grow the blocklist,
/// never shrink it — so this file is strictly accumulative until the block ends.
struct BlockAdditions: Codable {
    var domains: [String] = []
    var apps: [BlockedApp] = []
}

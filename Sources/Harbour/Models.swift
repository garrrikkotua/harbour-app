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
}

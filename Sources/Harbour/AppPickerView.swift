import SwiftUI
import AppKit

struct AppEntry: Identifiable, Hashable {
    let app: BlockedApp
    let icon: NSImage
    var id: String { app.path }

    static func == (lhs: AppEntry, rhs: AppEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AppPickerView: View {
    let alreadyAdded: Set<String>
    let onPick: (BlockedApp) -> Void
    let onCancel: () -> Void

    @State private var allApps: [AppEntry] = []
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 12)]

    private var filtered: [AppEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return allApps }
        return allApps.filter { $0.app.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(.separator), alignment: .bottom)

            if allApps.isEmpty {
                Spacer()
                ProgressView("Loading apps…").controlSize(.small)
                Spacer()
            } else if filtered.isEmpty {
                Spacer()
                Text("No apps match").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(filtered) { entry in
                            AppTile(
                                entry: entry,
                                isAdded: alreadyAdded.contains(entry.app.path),
                                action: { onPick(entry.app) }
                            )
                        }
                    }
                    .padding(12)
                }
            }

            Divider()
            HStack {
                Text("\(filtered.count) of \(allApps.count) apps")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(10)
        }
        .frame(width: 560, height: 480)
        .onAppear {
            loadApps()
            searchFocused = true
        }
    }

    private func loadApps() {
        Task.detached(priority: .userInitiated) {
            let apps = Self.scanApps()
            // Pre-load and pre-size icons off the main thread to avoid scroll jank.
            let entries: [AppEntry] = apps.map { app in
                let raw = NSWorkspace.shared.icon(forFile: app.path)
                let sized = NSImage(size: NSSize(width: 56, height: 56))
                sized.lockFocus()
                raw.draw(
                    in: NSRect(x: 0, y: 0, width: 56, height: 56),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1.0
                )
                sized.unlockFocus()
                return AppEntry(app: app, icon: sized)
            }
            await MainActor.run { self.allApps = entries }
        }
    }

    static func scanApps() -> [BlockedApp] {
        let homeApps = ("~/Applications" as NSString).expandingTildeInPath
        let roots = [
            "/Applications",
            "/System/Applications",
            homeApps,
        ]
        var seen = Set<String>()
        var results: [BlockedApp] = []
        for root in roots {
            collectApps(at: root, depth: 0, into: &results, seen: &seen)
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func collectApps(
        at dir: String,
        depth: Int,
        into results: inout [BlockedApp],
        seen: inout Set<String>
    ) {
        guard depth <= 2 else { return }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for item in items {
            let fullPath = "\(dir)/\(item)"
            if item.hasSuffix(".app") {
                if seen.contains(fullPath) { continue }
                if Safety.isCriticalApp(path: fullPath) { continue }
                seen.insert(fullPath)
                let bundleID = Bundle(path: fullPath)?.bundleIdentifier ?? ""
                let name = String(item.dropLast(4))
                results.append(BlockedApp(name: name, path: fullPath, bundleID: bundleID))
            } else {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue,
                   !item.hasPrefix(".")
                {
                    collectApps(at: fullPath, depth: depth + 1, into: &results, seen: &seen)
                }
            }
        }
    }
}

struct AppTile: View {
    let entry: AppEntry
    let isAdded: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: entry.icon)
                        .interpolation(.none)
                        .opacity(isAdded ? 0.45 : 1.0)
                    if isAdded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white, .green)
                            .offset(x: 4, y: -4)
                    }
                }
                .frame(width: 56, height: 56)
                Text(entry.app.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isAdded ? .secondary : .primary)
            }
            .frame(width: 96, height: 92)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering ? Color.secondary.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
        .onHover { hovering = $0 }
        .help(isAdded ? "Already added" : entry.app.path)
    }
}

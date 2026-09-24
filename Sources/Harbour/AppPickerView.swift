import SwiftUI
import AppKit
import HarbourCore

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
    @State private var loaded = false
    @State private var search = ""
    /// Picked in this sheet — shown as added right away, before the parent re-renders.
    @State private var picked: Set<String> = []
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 8)]

    private var filtered: [AppEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return allApps }
        return allApps.filter { $0.app.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title + search
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Add apps")
                        .font(Theme.serif(size: 20, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("Blocked apps close within a second of opening.")
                        .font(Theme.sans(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(searchFocused ? Theme.amber : Theme.textTertiary)
                    TextField("Search apps", text: $search)
                        .textFieldStyle(.plain)
                        .font(Theme.sans(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                        .focused($searchFocused)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                .strokeBorder(searchFocused ? Theme.amber.opacity(0.75) : Theme.creamBorder,
                                              lineWidth: searchFocused ? 1.5 : 1)
                        )
                )
                .animation(.easeOut(duration: 0.15), value: searchFocused)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(Theme.parchmentWarm)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.creamBorderSoft).frame(height: 1) }

            if !loaded {
                Spacer()
                ProgressView("Looking for apps…").controlSize(.small)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            } else if filtered.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.textTertiary)
                    Text(allApps.isEmpty ? "No apps found in /Applications" : "No apps match “\(search)”")
                        .font(Theme.sans(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(filtered) { entry in
                            AppTile(
                                entry: entry,
                                isAdded: alreadyAdded.contains(entry.app.path) || picked.contains(entry.app.path),
                                action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        _ = picked.insert(entry.app.path)
                                    }
                                    onPick(entry.app)
                                }
                            )
                        }
                    }
                    .padding(14)
                }
            }

            HStack {
                Text(loaded ? "\(filtered.count) of \(allApps.count) apps" : " ")
                    .font(Theme.sans(size: 11)).foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
                Spacer()
                // Picks apply immediately, so Done commits the sheet. Esc only:
                // Return belongs to the search field.
                Button("Done", action: onCancel)
                    .buttonStyle(HarbourCompactPrimaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.parchmentWarm)
            .overlay(alignment: .top) { Rectangle().fill(Theme.creamBorderSoft).frame(height: 1) }
        }
        // ~32 pt narrower than the 520 pt window so the sheet never overhangs it.
        .frame(width: 488, height: 480)
        .background(Theme.parchment)
        .environment(\.colorScheme, .light)
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
            await MainActor.run {
                self.allApps = entries
                self.loaded = true
            }
        }
    }

    nonisolated static func scanApps() -> [BlockedApp] {
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

    nonisolated private static func collectApps(
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
                        .interpolation(.high)
                        .opacity(isAdded ? 0.45 : 1.0)
                        .scaleEffect(hovering && !isAdded ? 1.06 : 1)
                    if isAdded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white, Theme.amber)
                            .offset(x: 4, y: -4)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .frame(width: 56, height: 56)
                Text(entry.app.name)
                    .font(Theme.sans(size: 11))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isAdded ? Theme.textTertiary : Theme.textPrimary)
                    // Fixed label box: one- and two-line names keep icons on one baseline.
                    .frame(height: 28, alignment: .top)
            }
            .frame(width: 96, height: 92, alignment: .top)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering && !isAdded ? Color.white : Color.clear)
                    .shadow(color: Theme.navy.opacity(hovering && !isAdded ? 0.08 : 0), radius: 6, y: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(isAdded ? "Already added" : entry.app.path)
        .accessibilityLabel(isAdded ? "\(entry.app.name), added" : "Add \(entry.app.name)")
    }
}

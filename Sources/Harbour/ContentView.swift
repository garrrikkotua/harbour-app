import SwiftUI
import AppKit
import HarbourCore

struct ContentView: View {
    @ObservedObject var manager: BlockManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True once the setup screen has been shown in this window. Only a block
    /// started from here plays the ignition; relaunching mid-session doesn't.
    @State private var sawSetup = false

    var body: some View {
        ZStack {
            if manager.isActive {
                ActiveView(manager: manager, ignite: sawSetup && !reduceMotion)
                    .transition(.opacity)
            } else {
                SetupView(manager: manager)
                    .onAppear { sawSetup = true }
                    .transition(.opacity)
            }
        }
        .frame(width: 520, height: 640)
        // No .clipped(): the backgrounds extend under the hidden title bar,
        // and the window itself clips the beam.
        // Parchment fades to night while the lamp ignites; Reduce Motion gets a quick crossfade.
        .animation(.easeInOut(duration: reduceMotion ? 0.3 : 0.9), value: manager.isActive)
    }
}

// MARK: - Setup

struct SetupView: View {
    @ObservedObject var manager: BlockManager
    @State private var newDomain = ""
    @State private var showAppPicker = false
    @State private var showFAQ = false
    @State private var showConfirm = false
    @State private var errorMessage: String?
    @State private var startHovered = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    Hero(
                        lampLit: startHovered && canStart,
                        onHelp: { showFAQ = true }
                    )

                    DomainSection(manager: manager, newDomain: $newDomain)

                    AppsSection(manager: manager, onAddTap: { showAppPicker = true })

                    DurationSection(manager: manager)
                }
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)

            footer
        }
        .frame(width: 520, height: 640)
        .background(Theme.setupBackground.ignoresSafeArea())
        // The app paints its own parchment palette; keep AppKit controls
        // (text fields, menus) in light mode so they stay readable.
        .environment(\.colorScheme, .light)
        .onAppear {
            // Demo/QA only (see DemoMode): open a sheet for screenshots.
            switch DemoMode.sheet {
            case .confirm: showConfirm = canStart
            case .faq: showFAQ = true
            case .apps: showAppPicker = true
            case nil: break
            }
        }
        .sheet(isPresented: $showAppPicker) {
            AppPickerView(
                alreadyAdded: Set(manager.config.apps.map(\.path)),
                onPick: { app in
                    guard !manager.config.apps.contains(where: { $0.path == app.path }) else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        manager.config.apps.insert(app, at: 0)
                    }
                    manager.saveConfig()
                },
                onCancel: { showAppPicker = false }
            )
        }
        .sheet(isPresented: $showFAQ) {
            FAQView(onClose: { showFAQ = false })
        }
        .sheet(isPresented: $showConfirm) {
            ConfirmView(
                durationMinutes: manager.config.durationMinutes,
                domainCount: manager.config.domains.count,
                appCount: manager.config.apps.count,
                riskyDomains: Safety.riskyEntries(from: manager.config.domains),
                sharedNetworks: Safety.sharedNetworks(in: manager.config.domains),
                onCancel: { showConfirm = false },
                onConfirm: {
                    showConfirm = false
                    startBlock()
                },
                domains: manager.config.domains,
                appNames: manager.config.apps.map(\.name)
            )
        }
    }

    /// Pinned call to action so "Start block" is always in reach, whatever
    /// the list lengths.
    private var footer: some View {
        VStack(spacing: 7) {
            if let error = errorMessage {
                ErrorBanner(message: error, onDismiss: { errorMessage = nil })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            StartButton(
                title: manager.isStarting ? "Waiting for authorization…" : "Start block",
                detail: manager.isStarting ? nil : DurationText.short(manager.config.durationMinutes),
                enabled: canStart,
                busy: manager.isStarting,
                action: { showConfirm = true }
            )
            .onHover { startHovered = $0 }

            Text(footnote)
                .font(Theme.sans(size: 11))
                .foregroundStyle(hasSelection ? Theme.textTertiary : Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            Theme.parchment.opacity(0.94)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.creamBorderSoft.opacity(0.7)).frame(height: 1)
                }
        )
        // Content scrolling under the footer fades out instead of being cut.
        .background(alignment: .top) {
            LinearGradient(colors: [Theme.parchmentDeep.opacity(0), Theme.parchmentDeep.opacity(0.9)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
                .offset(y: -22)
                .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: errorMessage)
    }

    private var hasSelection: Bool {
        !(manager.config.domains.isEmpty && manager.config.apps.isEmpty)
    }

    private var canStart: Bool {
        !manager.isStarting && (1...1440).contains(manager.config.durationMinutes) && hasSelection
    }

    private var footnote: String {
        hasSelection
            ? "macOS will ask for your administrator password. There's no early cancel."
            : "Add at least one website or app to start."
    }

    private func startBlock() {
        errorMessage = nil
        Task {
            do {
                try await manager.startBlock()
                errorMessage = nil
            } catch HarbourError.installCancelled {
                errorMessage = "Authorization was cancelled, so nothing was started."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Hero

private struct Hero: View {
    let lampLit: Bool
    let onHelp: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // A small window onto the night scene: the same lighthouse as the
            // intro and the session, its lamp banked low until you hover
            // "Start block".
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.activeBackground)
                StarfieldView(count: 9, heightFraction: 0.5)
                IntroLighthouse(size: 52, lamp: lampLit ? 1 : 0.25)
                    .offset(y: 5)
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: (lampLit ? Theme.beam : Theme.navy).opacity(lampLit ? 0.45 : 0.22),
                    radius: lampLit ? 14 : 8, y: 4)
            .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.55), value: lampLit)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: "Harbour Control", glow: lampLit)
                    .animation(.easeOut(duration: 0.3), value: lampLit)
                Text("Start a block")
                    .font(Theme.serif(size: 30, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Pick what to block. It stays locked until the timer ends.")
                    .font(Theme.sans(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            CircleIconButton(symbol: "questionmark", tint: Theme.textSecondary,
                             hoverFill: Theme.navySoft, help: "How Harbour Control works",
                             action: onHelp)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Section chrome

private struct SectionHeader: View {
    let title: String
    var count: Int? = nil
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title.uppercased())
                .font(Theme.sans(size: 10, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.textSecondary)
            if let count, count > 0 {
                Text("\(count)")
                    .font(Theme.sans(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.amberSoft))
                    .numericTransition()
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.sans(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 4)
        .animation(.easeOut(duration: 0.2), value: count)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(CardBackground())
    }
}

private struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.creamBorderSoft)
            .frame(height: 1)
    }
}

private struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.cream))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.sans(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(detail)
                    .font(Theme.sans(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .transition(.opacity)
    }
}

// MARK: - Domain input helpers (shared by setup and live add)

struct FieldHint: Equatable {
    enum Kind { case info, error }
    let kind: Kind
    let text: String
}

enum DomainInput {
    /// Split pasted text ("a.com, b.com\nc.com") into normalised hostnames.
    static func parse(_ text: String, existing: Set<String>)
        -> (valid: [String], duplicates: [String], invalid: [String])
    {
        let parts = text
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
            .map(String.init)
        var valid: [String] = [], duplicates: [String] = [], invalid: [String] = []
        var seen = existing
        for part in parts {
            guard let d = DomainValidation.normalizedDomain(part),
                  DomainValidation.isSafeDomain(d), d.contains(".") else {
                invalid.append(part)
                continue
            }
            if seen.contains(d) { duplicates.append(d); continue }
            seen.insert(d)
            valid.append(d)
        }
        return (valid, duplicates, invalid)
    }

    static func hint(valid: [String], duplicates: [String], invalid: [String], live: Bool) -> FieldHint? {
        if let bad = invalid.first, valid.isEmpty {
            return FieldHint(kind: .error, text: "“\(bad)” isn't a website address. Try something like example.com.")
        }
        if valid.isEmpty, let dupe = duplicates.first {
            return FieldHint(kind: .info, text: "\(dupe) is already on the list.")
        }
        var notes: [String] = []
        if live, !valid.isEmpty {
            notes.append(valid.count == 1 ? "Added \(valid[0]). It stays blocked until the timer ends."
                                          : "Added \(valid.count) sites. They stay blocked until the timer ends.")
        }
        if !invalid.isEmpty { notes.append("Skipped \(invalid.count) invalid \(invalid.count == 1 ? "entry" : "entries").") }
        if !duplicates.isEmpty { notes.append("\(duplicates.count) already listed.") }
        guard !notes.isEmpty else { return nil }
        return FieldHint(kind: invalid.isEmpty ? .info : .error, text: notes.joined(separator: " "))
    }
}

private struct HintLine: View {
    let hint: FieldHint
    var infoColor: Color = Theme.textSecondary
    var errorColor: Color = Theme.ember

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: hint.kind == .error ? "exclamationmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 10))
            Text(hint.text)
                .font(Theme.sans(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(hint.kind == .error ? errorColor : infoColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Plain text field with a soft well and an amber focus ring.
private struct HarbourTextField: View {
    let placeholder: String
    @Binding var text: String
    var dark = false
    let onSubmit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Theme.sans(size: 13))
            .foregroundStyle(dark ? Theme.nightText : Theme.textPrimary)
            .focused($focused)
            .onSubmit(onSubmit)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(dark ? Color.white.opacity(0.07) : Theme.cream.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(
                        focused ? (dark ? Theme.beam.opacity(0.7) : Theme.amber.opacity(0.75))
                                : (dark ? Color.white.opacity(0.12) : Theme.creamBorder),
                        lineWidth: focused ? 1.5 : 1
                    )
            )
            .shadow(color: Theme.beam.opacity(focused ? 0.25 : 0), radius: 5)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

// MARK: - Domains

private struct DomainSection: View {
    @ObservedObject var manager: BlockManager
    @Binding var newDomain: String
    @State private var hint: FieldHint?
    @State private var flashed: String?

    private let rowHeight: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Websites", count: manager.config.domains.count)
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        HarbourTextField(placeholder: "twitter.com, youtube.com…", text: $newDomain, onSubmit: add)
                        Button("Add", action: add)
                            .buttonStyle(HarbourSecondaryButtonStyle())
                            .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                        presetsMenu
                    }
                    if let hint {
                        HintLine(hint: hint)
                    }
                }
                .padding(10)

                CardDivider()

                if manager.config.domains.isEmpty {
                    EmptyState(symbol: "globe",
                               title: "No websites yet",
                               detail: "Type a domain above or start from a preset.")
                } else {
                    list
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: hint)
        // Typing clears the last message; clearing the field after a
        // successful add must not.
        .onChange(of: newDomain) { text in
            if !text.isEmpty, hint != nil { hint = nil }
        }
        .task(id: hint) {
            // Confirmations fade on their own; errors stay until the next edit.
            guard hint?.kind == .info else { return }
            guard (try? await Task.sleep(nanoseconds: 4_000_000_000)) != nil else { return }
            hint = nil
        }
    }

    private var list: some View {
        let domains = manager.config.domains
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(domains, id: \.self) { domain in
                        EntryRow(title: domain, highlighted: flashed == domain, onRemove: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                manager.config.domains.removeAll { $0 == domain }
                            }
                            manager.saveConfig()
                        }) {
                            FaviconView(domain: domain, size: 20)
                        }
                        .id(domain)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(domains.count > 3 ? .automatic : .never)
            .frame(height: min(CGFloat(domains.count), 3) * rowHeight + 8)
            .modifier(OverflowFade(active: domains.count > 3))
            .onChange(of: flashed) { target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }

    private var presetsMenu: some View {
        Menu {
            ForEach(DomainPreset.allCases) { p in
                let missing = p.domains.filter { !manager.config.domains.contains($0) }.count
                Button {
                    addPreset(p)
                } label: {
                    Label(
                        missing == 0 ? "\(p.rawValue) — all added" : "\(p.rawValue) — \(missing) sites",
                        systemImage: missing == 0 ? "checkmark" : p.symbol
                    )
                }
                .disabled(missing == 0)
            }
        } label: {
            Label("Presets", systemImage: "sparkles")
                .font(Theme.sans(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(Theme.cream)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(Theme.creamBorder, lineWidth: 1)
                )
        )
        .tint(Theme.navy)
        .help("Add a curated list of distracting sites")
    }

    private func add() {
        let text = newDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let result = DomainInput.parse(text, existing: Set(manager.config.domains))
        hint = DomainInput.hint(valid: result.valid, duplicates: result.duplicates,
                                invalid: result.invalid, live: false)
        if !result.valid.isEmpty {
            // Newest first, so fresh entries land in view.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                manager.config.domains.insert(contentsOf: result.valid, at: 0)
            }
            manager.saveConfig()
        } else if let dupe = result.duplicates.first {
            flash(dupe)
        }
        if result.invalid.isEmpty { newDomain = "" }
    }

    private func addPreset(_ p: DomainPreset) {
        let fresh = p.domains.filter { !manager.config.domains.contains($0) }
        guard !fresh.isEmpty else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            manager.config.domains.insert(contentsOf: fresh, at: 0)
        }
        manager.saveConfig()
        hint = FieldHint(kind: .info, text: "Added \(fresh.count) from \(p.rawValue).")
    }

    private func flash(_ domain: String) {
        flashed = domain
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.4)) {
                if flashed == domain { flashed = nil }
            }
        }
    }
}

/// Fades the last rows of a capped list so it reads as "scroll for more"
/// rather than a row cut off against the card border.
private struct OverflowFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.7),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        } else {
            content
        }
    }
}

/// One removable entry in a setup list. Hover tints the row and brings the
/// remove button forward.
private struct EntryRow<Leading: View>: View {
    let title: String
    var highlighted = false
    let onRemove: () -> Void
    @ViewBuilder var leading: () -> Leading

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            leading()
                .frame(width: 20, height: 20)
            Text(title)
                .font(Theme.sans(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textTertiary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(hovering ? Theme.cream : Color.clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.55)
            .help("Remove \(title)")
            .accessibilityLabel("Remove \(title)")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(highlighted ? Theme.amberSoft : (hovering ? Theme.navySoft.opacity(0.7) : Color.clear))
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Apps

private struct AppsSection: View {
    @ObservedObject var manager: BlockManager
    let onAddTap: () -> Void

    private let rowHeight: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Apps", count: manager.config.apps.count)
            Card {
                AddAppRow(action: onAddTap)

                CardDivider()

                if manager.config.apps.isEmpty {
                    EmptyState(symbol: "square.grid.2x2",
                               title: "No apps blocked",
                               detail: "Blocked apps close within a second of opening.")
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(manager.config.apps) { app in
                                EntryRow(title: app.name, onRemove: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                        manager.config.apps.removeAll { $0.path == app.path }
                                    }
                                    manager.saveConfig()
                                }) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                        .resizable().interpolation(.high)
                                }
                                .help(app.path)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(manager.config.apps.count > 2 ? .automatic : .never)
                    .frame(height: min(CGFloat(manager.config.apps.count), 2) * rowHeight + 8)
                    .modifier(OverflowFade(active: manager.config.apps.count > 2))
                }
            }
        }
    }
}

private struct AddAppRow: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.parchmentWarm)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Theme.primaryButton))
                    .scaleEffect(hovering ? 1.08 : 1)
                Text("Add app…")
                    .font(Theme.sans(size: 13, weight: .medium))
                    .foregroundStyle(Theme.navy)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .offset(x: hovering ? 2 : 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(hovering ? Theme.navySoft.opacity(0.55) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Duration

enum DurationText {
    /// "1 h 30 min", "45 min", "24 h"
    static func short(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h) h"
        default: return "\(h) h \(m) min"
        }
    }

    /// Chip-sized: "5m", "2h", "1h 30m"
    static func compact(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m)m"
        case (_, 0): return "\(h)h"
        default: return "\(h)h \(m)m"
        }
    }

    /// "1 hour 30 minutes"
    static func long(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        let hours = h == 1 ? "1 hour" : "\(h) hours"
        let mins = m == 1 ? "1 minute" : "\(m) minutes"
        switch (h, m) {
        case (0, _): return mins
        case (_, 0): return hours
        default: return "\(hours) \(mins)"
        }
    }

    /// "4:30 PM", "tomorrow at 4:30 PM", "Sat, Oct 3 at 4:30 PM"
    static func endPhrase(_ date: Date, now: Date = Date()) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow at \(time)"
        }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) at \(time)"
    }
}

private struct DurationSection: View {
    @ObservedObject var manager: BlockManager
    @Namespace private var chipSpace

    private let presets: [(String, Int)] = [
        ("15m", 15), ("30m", 30), ("1h", 60), ("2h", 120),
        ("4h", 240), ("8h", 480), ("24h", 1440),
    ]

    private var minutes: Int { manager.config.durationMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.everyMinute) { context in
                let end = context.date.addingTimeInterval(TimeInterval(minutes * 60))
                SectionHeader(title: "Duration",
                              trailing: "Start now, ends \(DurationText.endPhrase(end, now: context.date))")
            }
            Card {
                VStack(spacing: 10) {
                    chips

                    HStack(alignment: .center, spacing: 10) {
                        DurationSpinner(
                            label: "HOURS",
                            value: minutes / 60,
                            format: "%d",
                            onMinus: { nudge(hours: -1) },
                            onPlus:  { nudge(hours: 1) },
                            canMinus: minutes > 5,
                            canPlus:  minutes + 60 <= 1440
                        )
                        Text(":")
                            .font(Theme.serif(size: 30, weight: .light))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.bottom, 22)
                        DurationSpinner(
                            label: "MINUTES",
                            value: minutes % 60,
                            format: "%02d",
                            onMinus: { nudge(minutes: -5) },
                            onPlus:  { nudge(minutes: 5) },
                            canMinus: minutes > 5,
                            canPlus:  minutes < 1440
                        )
                    }
                }
                .padding(10)
            }
        }
    }

    /// Presets, plus the current duration as its own chip when it isn't one
    /// of them, so the selection is always visible.
    private var chipItems: [(String, Int)] {
        guard !presets.contains(where: { $0.1 == minutes }) else { return presets }
        return (presets + [(DurationText.compact(minutes), minutes)]).sorted { $0.1 < $1.1 }
    }

    private var chips: some View {
        HStack(spacing: 2) {
            ForEach(chipItems, id: \.1) { label, value in
                DurationChip(
                    label: label,
                    selected: minutes == value,
                    namespace: chipSpace
                ) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        manager.config.durationMinutes = value
                    }
                    manager.saveConfig()
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.cream.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.creamBorderSoft, lineWidth: 1)
                )
        )
    }

    private func nudge(hours: Int = 0, minutes: Int = 0) {
        let total = manager.config.durationMinutes + hours * 60 + minutes
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            manager.config.durationMinutes = max(5, min(1440, total))
        }
        manager.saveConfig()
    }
}

/// Segment with a navy pill that slides between selections.
private struct DurationChip: View {
    let label: String
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.sans(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Theme.parchmentWarm : (hovering ? Theme.textPrimary : Theme.textSecondary))
                .frame(maxWidth: .infinity, minHeight: 28)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.primaryButton)
                            .shadow(color: Theme.navy.opacity(0.25), radius: 4, y: 2)
                            .matchedGeometryEffect(id: "selectedChip", in: namespace)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.8))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct DurationSpinner: View {
    let label: String
    let value: Int
    let format: String
    let onMinus: () -> Void
    let onPlus: () -> Void
    let canMinus: Bool
    let canPlus: Bool

    var body: some View {
        HStack(spacing: 12) {
            SpinnerButton(symbol: "minus", label: "Fewer \(label.lowercased())", action: onMinus, enabled: canMinus)
            VStack(spacing: 0) {
                Text(String(format: format, value))
                    .font(Theme.serif(size: 30, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .numericTransition()
                    .frame(minWidth: 48)
                Text(label)
                    .font(Theme.sans(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
            }
            SpinnerButton(symbol: "plus", label: "More \(label.lowercased())", action: onPlus, enabled: canPlus)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.parchment.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.creamBorderSoft, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
    }
}

private struct SpinnerButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    let enabled: Bool

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(enabled ? Theme.navy : Theme.textTertiary.opacity(0.6))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(enabled ? (hovering ? Color.white : Theme.navySoft) : Theme.cream.opacity(0.6))
                        .overlay(Circle().strokeBorder(Theme.navy.opacity(enabled && hovering ? 0.2 : 0.08), lineWidth: 1))
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(label)
    }
}

// MARK: - Buttons

/// Shrinks slightly while pressed.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Main call to action: navy with an amber lamp glow on hover.
private struct StartButton: View {
    let title: String
    let detail: String?
    let enabled: Bool
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                if let detail {
                    Text(detail)
                        .font(Theme.sans(size: 13, weight: .medium))
                        .opacity(0.65)
                        .numericTransition()
                }
            }
        }
        .buttonStyle(GlowButtonStyle(fill: Theme.primaryButton))
        .disabled(!enabled)
        .keyboardShortcut(.return, modifiers: .command)
        .help(enabled ? "Review and start (⌘↩)" : "")
    }
}

/// Large filled button used for primary and irreversible actions. Hover adds
/// a warm glow and ring; press sinks it slightly.
struct GlowButtonStyle: ButtonStyle {
    var fill: LinearGradient
    var glow: Color = Theme.beam
    var height: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        GlowButtonBody(configuration: configuration, fill: fill, glow: glow, height: height)
    }

    private struct GlowButtonBody: View {
        let configuration: Configuration
        let fill: LinearGradient
        let glow: Color
        let height: CGFloat

        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let lit = hovering && isEnabled
            configuration.label
                .font(Theme.sans(size: 15, weight: .semibold))
                .foregroundStyle(Theme.parchmentWarm.opacity(isEnabled ? 1 : 0.85))
                .frame(maxWidth: .infinity, minHeight: height)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isEnabled ? AnyShapeStyle(fill) : AnyShapeStyle(Theme.textTertiary.opacity(0.5)))
                )
                .overlay(
                    // Top sheen, like light catching the lacquer.
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.02)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(glow.opacity(lit ? 0.6 : 0), lineWidth: 1)
                )
                .shadow(color: (lit ? glow : Theme.navy).opacity(isEnabled ? (lit ? 0.38 : 0.22) : 0),
                        radius: lit ? 16 : 10, y: lit ? 5 : 5)
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .brightness(configuration.isPressed ? -0.04 : 0)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.2), value: lit)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// Kept for callers that want the plain primary button.
struct PrimaryButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(GlowButtonStyle(fill: Theme.primaryButton))
            .disabled(!enabled)
    }
}

struct HarbourSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryBody(configuration: configuration)
    }

    private struct SecondaryBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Theme.sans(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? Theme.navy : Theme.textTertiary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(hovering && isEnabled ? Color.white : Theme.cream)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                .strokeBorder(hovering && isEnabled ? Theme.navy.opacity(0.22) : Theme.creamBorder,
                                              lineWidth: 1)
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

/// Small navy button that commits a sheet (e.g. "Done").
struct HarbourCompactPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CompactPrimaryBody(configuration: configuration)
    }

    private struct CompactPrimaryBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Theme.sans(size: 12, weight: .semibold))
                .foregroundStyle(Theme.parchmentWarm)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(Theme.primaryButton)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                .strokeBorder(Theme.beam.opacity(hovering ? 0.5 : 0), lineWidth: 1)
                        )
                )
                .shadow(color: (hovering ? Theme.beam : Theme.navy).opacity(hovering ? 0.3 : 0.18),
                        radius: hovering ? 8 : 4, y: 2)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .brightness(configuration.isPressed ? -0.04 : 0)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

/// Round icon-only button (help, close).
struct CircleIconButton: View {
    let symbol: String
    var tint: Color = Theme.textSecondary
    var hoverFill: Color = Theme.navySoft
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint.opacity(hovering ? 1 : 0.8))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(hovering ? hoverFill : Color.clear)
                        .overlay(Circle().strokeBorder(tint.opacity(hovering ? 0.25 : 0.2), lineWidth: 1))
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.ember)
            Text(message)
                .font(Theme.sans(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.ember.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.ember.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Active

struct ActiveView: View {
    @ObservedObject var manager: BlockManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showFAQ = false
    @State private var showAppPicker = false
    @State private var expanded = false
    @State private var newDomain = ""
    @State private var windowVisible = true
    /// When the lamp was lit (ignition), nil if the session was already running.
    @State private var ignitedAt: Date?
    @State private var revealed: Bool

    init(manager: BlockManager, ignite: Bool = false) {
        self.manager = manager
        _ignitedAt = State(initialValue: ignite ? Date() : nil)
        _revealed = State(initialValue: !ignite)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.activeBackground.ignoresSafeArea()
            StarfieldView(animated: windowVisible)
                // Quieter sky behind the countdown so stars never sit on the text.
                .mask(
                    RadialGradient(
                        stops: [
                            .init(color: .black.opacity(0.35), location: 0),
                            .init(color: .black.opacity(0.35), location: 150.0 / 220),
                            .init(color: .black, location: 1),
                        ],
                        center: UnitPoint(x: 0.5, y: 0.47),
                        startRadius: 0, endRadius: 220
                    )
                )
                .mask(Self.topFade)

            VStack {
                Spacer()
                SeaWavesView(animated: windowVisible)
                    .frame(height: 72)
            }

            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LighthouseIcon(
                        size: 116,
                        sweeping: true,
                        beamReach: 2.0,
                        ignitedAt: ignitedAt,
                        animated: windowVisible
                    )
                    .padding(.top, 76)

                    VStack(spacing: 0) {
                        VStack(spacing: 4) {
                            Text("Blocking")
                                .font(Theme.serif(size: 30, weight: .bold))
                                .foregroundStyle(Theme.nightText)
                            Text("You're in a focused session.")
                                .font(Theme.sans(size: 13))
                                .foregroundStyle(Theme.nightSecondary)
                        }
                        .padding(.top, 14)

                        Countdown(seconds: manager.remainingSeconds)
                            .padding(.top, 10)

                        ProgressTrack(progress: progress, animated: windowVisible)
                            .frame(height: 6)
                            .padding(.horizontal, 30)
                            .padding(.top, 8)

                        if let state = manager.currentState {
                            HStack(spacing: 26) {
                                ActiveStat(symbol: "globe", count: manager.effectiveDomains.count,
                                           singular: "site", plural: "sites")
                                ActiveStat(symbol: "square.grid.2x2.fill", count: manager.effectiveApps.count,
                                           singular: "app", plural: "apps")
                            }
                            .padding(.top, 18)

                            Text("Ends \(DurationText.endPhrase(state.endTime))")
                                .font(Theme.sans(size: 12))
                                .foregroundStyle(Theme.nightTertiary)
                                .padding(.top, 8)
                        }

                        BlocklistSection(
                            manager: manager,
                            expanded: $expanded,
                            newDomain: $newDomain,
                            onAddApp: { showAppPicker = true }
                        )
                        .padding(.top, 30)
                        .id("blocklist")
                    }
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 10)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 64)
            }
            .scrollIndicators(.never)
            // Nothing bright (beam, scrolled rows) under the traffic lights.
            .mask(Self.topFade)
            .onChange(of: expanded) { isOpen in
                // Bring the add field and list into view once the section has opened.
                guard isOpen else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo("blocklist", anchor: .bottom) }
                }
            }
            }

            HStack {
                Spacer()
                CircleIconButton(symbol: "questionmark", tint: Color.white.opacity(0.75),
                                 hoverFill: Color.white.opacity(0.1), help: "How Harbour Control works",
                                 action: { showFAQ = true })
            }
            .padding(14)
        }
        .frame(width: 520, height: 640)
        .environment(\.colorScheme, .dark)
        .trackingWindowVisibility($windowVisible)
        .onAppear {
            guard !revealed else { return }
            // Let the lamp catch first, then bring the numbers up.
            withAnimation(.easeOut(duration: 0.7).delay(0.6)) { revealed = true }
        }
        .onAppear {
            // Demo/QA only (see DemoMode).
            if DemoMode.sheet == .faq { showFAQ = true }
            if DemoMode.sheet == .apps { showAppPicker = true }
        }
        .sheet(isPresented: $showFAQ) { FAQView(onClose: { showFAQ = false }) }
        .sheet(isPresented: $showAppPicker) {
            AppPickerView(
                alreadyAdded: Set(manager.effectiveApps.map(\.path)),
                onPick: { app in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        manager.addAppLive(app)
                    }
                },
                onCancel: { showAppPicker = false }
            )
        }
    }

    /// Clear under the title bar, fully opaque from 90 pt down.
    static let topFade = LinearGradient(
        stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: 40.0 / 640),
            .init(color: .black, location: 90.0 / 640),
            .init(color: .black, location: 1),
        ],
        startPoint: .top, endPoint: .bottom
    )

    private var progress: Double {
        guard let state = manager.currentState else { return 0 }
        let total = state.endTime.timeIntervalSince(state.startTime)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(state.startTime)
        return min(1, max(0, elapsed / total))
    }
}

private struct Countdown: View {
    let seconds: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        Text(String(format: "%02d:%02d:%02d", h, m, s))
            .font(Theme.serif(size: 56, weight: .semibold))
            .tracking(-0.5)
            .monospacedDigit()
            .foregroundStyle(Theme.nightText)
            .shadow(color: Theme.beam.opacity(0.18), radius: 14)
            .numericTransition(countsDown: true)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: seconds)
            .accessibilityLabel("\(h) hours \(m) minutes \(s) seconds left")
    }
}

// MARK: - Blocklist section (active block — can only add, never remove)

private struct BlocklistSection: View {
    @ObservedObject var manager: BlockManager
    @Binding var expanded: Bool
    @Binding var newDomain: String
    let onAddApp: () -> Void

    @State private var hint: FieldHint?
    @State private var headerHover = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    addControls
                    if let hint {
                        HintLine(hint: hint, infoColor: Theme.nightSecondary, errorColor: Theme.beam)
                    }
                    listBody
                    Text("New entries are enforced within seconds and stay until the timer ends.")
                        .font(Theme.sans(size: 10))
                        .foregroundStyle(Theme.nightTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(headerHover && !expanded ? 0.08 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: expanded)
        .animation(.easeOut(duration: 0.2), value: hint)
        // Typing clears the last message; clearing the field after a
        // successful add must not.
        .onChange(of: newDomain) { text in
            if !text.isEmpty, hint != nil { hint = nil }
        }
        .task(id: hint) {
            // Confirmations fade on their own; errors stay until the next edit.
            guard hint?.kind == .info else { return }
            guard (try? await Task.sleep(nanoseconds: 4_000_000_000)) != nil else { return }
            hint = nil
        }
    }

    private var header: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.beam.opacity(0.85))
                Text("Manage blocklist")
                    .font(Theme.sans(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.white.opacity(0.78))
                Spacer()
                Text("add only · no take-backs")
                    .font(Theme.sans(size: 10))
                    .foregroundStyle(Color.white.opacity(0.4))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { headerHover = $0 }
        .animation(.easeOut(duration: 0.15), value: headerHover)
        .accessibilityLabel(expanded ? "Hide blocklist" : "Manage blocklist, add only")
    }

    private var addControls: some View {
        HStack(spacing: 8) {
            HarbourTextField(placeholder: "another-site.com", text: $newDomain, dark: true,
                             onSubmit: addDomainAction)

            Button("Add site", action: addDomainAction)
                .buttonStyle(AddButtonStyle())
                .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)

            Button(action: onAddApp) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.app")
                    Text("Add app")
                }
            }
            .buttonStyle(AddButtonStyle())
        }
    }

    private func addDomainAction() {
        let text = newDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let result = DomainInput.parse(text, existing: Set(manager.effectiveDomains))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            for d in result.valid { manager.addDomainLive(d) }
        }
        hint = DomainInput.hint(valid: result.valid, duplicates: result.duplicates,
                                invalid: result.invalid, live: true)
        if result.invalid.isEmpty { newDomain = "" }
    }

    private var listBody: some View {
        let domains = manager.effectiveDomains
        let apps = manager.effectiveApps
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if !domains.isEmpty {
                    ListCaption(text: "Websites", count: domains.count)
                    ForEach(domains, id: \.self) { d in
                        BlocklistRow(icon: .domain(d), label: d)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                if !apps.isEmpty {
                    ListCaption(text: "Apps", count: apps.count)
                        .padding(.top, domains.isEmpty ? 0 : 8)
                    ForEach(apps) { app in
                        BlocklistRow(icon: .app(app.path), label: app.name)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                if domains.isEmpty && apps.isEmpty {
                    Text("Blocklist is empty.")
                        .font(Theme.sans(size: 12))
                        .foregroundStyle(Theme.nightTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: 190)
        .fixedSize(horizontal: false, vertical: domains.count + apps.count < 6)
    }
}

private struct ListCaption: View {
    let text: String
    let count: Int

    var body: some View {
        Text("\(text.uppercased()) · \(count)")
            .font(Theme.sans(size: 9, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.nightTertiary)
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
    }
}

private enum BlocklistIcon {
    case domain(String)
    case app(String)
}

private struct BlocklistRow: View {
    let icon: BlocklistIcon
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 18, height: 18)
            Text(label)
                .font(Theme.sans(size: 12))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.25))
                .accessibilityLabel("Locked")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .domain(let d):
            FaviconView(domain: d, size: 18)
        case .app(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable().interpolation(.high)
                .frame(width: 18, height: 18)
        }
    }
}

private struct AddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AddButtonBody(configuration: configuration)
    }

    private struct AddButtonBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Theme.sans(size: 11, weight: .semibold))
                .foregroundStyle(Theme.parchmentWarm.opacity(isEnabled ? 1 : 0.45))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(Color.white.opacity(configuration.isPressed ? 0.26 : (hovering && isEnabled ? 0.2 : 0.13)))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                .strokeBorder(Color.white.opacity(hovering && isEnabled ? 0.28 : 0.16), lineWidth: 1)
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// Amber → lamp-glow progress with a rare glint and a glowing head.
private struct ProgressTrack: View {
    let progress: Double
    var animated: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let live = animated && !reduceMotion
        GeometryReader { geo in
            let width = max(6, geo.size.width * progress)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))

                Capsule()
                    .fill(Theme.progressFill)
                    .frame(width: width)
                    .overlay(alignment: .leading) {
                        if live {
                            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                                // A faint 2.8 s glint every 12 s; resting the rest of
                                // the time so it never reads as a loading bar.
                                let cycle = context.date.timeIntervalSinceReferenceDate
                                    .truncatingRemainder(dividingBy: 12.0) / 2.8
                                let band: CGFloat = 70
                                LinearGradient(
                                    colors: [.white.opacity(0), .white.opacity(0.25), .white.opacity(0)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                                .frame(width: band)
                                .offset(x: -band + (width + band) * CGFloat(min(1, cycle)))
                            }
                        }
                    }
                    .clipShape(Capsule())
                    .shadow(color: Theme.beam.opacity(0.35), radius: 6)

                // Glowing head
                Circle()
                    .fill(Theme.beam)
                    .frame(width: 8, height: 8)
                    .shadow(color: Theme.beam.opacity(0.9), radius: 5)
                    .offset(x: width - 7)
            }
            .animation(.linear(duration: 0.9), value: progress)
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

private struct ActiveStat: View {
    let symbol: String
    let count: Int
    let singular: String
    let plural: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.beam.opacity(0.8))
            (Text("\(count)")
                .font(Theme.sans(size: 13, weight: .semibold))
                .monospacedDigit()
             + Text(" \(count == 1 ? singular : plural)")
                .font(Theme.sans(size: 13)))
                .numericTransition()
        }
        .foregroundStyle(Color.white.opacity(0.78))
        .animation(.easeOut(duration: 0.25), value: count)
    }
}

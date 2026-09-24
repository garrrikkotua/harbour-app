import SwiftUI
import HarbourCore

/// Last stop before an irreversible block. Spells out exactly what will be
/// locked, for how long, and that there is no way to stop it early.
struct ConfirmView: View {
    let durationMinutes: Int
    let domainCount: Int
    let appCount: Int
    let riskyDomains: [String]
    /// Companies whose other services share the blocked servers.
    var sharedNetworks: [Safety.SharedNetwork] = []
    let onCancel: () -> Void
    let onConfirm: () -> Void
    /// Optional detail for the summary. Counts above stay authoritative.
    var domains: [String] = []
    var appNames: [String] = []

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 26)
                .padding(.horizontal, 28)

            VStack(spacing: 12) {
                summaryCard
                warningCallout
                if !riskyDomains.isEmpty { riskyCallout }
                if !sharedNetworks.isEmpty { sharedCallout }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            buttons
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 22)
        }
        .frame(width: 440)
        .background(Theme.parchment)
        .environment(\.colorScheme, .light)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.activeBackground)
                LighthouseIcon(size: 52, pulsing: true)
                    .offset(y: 4)
            }
            .frame(width: 68, height: 68)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            .shadow(color: Theme.navy.opacity(0.3), radius: 10, y: 4)
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)

            Eyebrow(text: "Point of no return", color: Theme.ember)
                .padding(.top, 4)

            Text("Lock in \(DurationText.long(durationMinutes))?")
                .font(Theme.serif(size: 24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        TimelineView(.everyMinute) { context in
            let end = context.date.addingTimeInterval(TimeInterval(durationMinutes * 60))
            VStack(spacing: 0) {
                SummaryRow(
                    symbol: "globe",
                    title: count(domainCount, "website", "websites"),
                    detail: preview(domains, total: domainCount, none: "No websites")
                )
                Rectangle().fill(Theme.creamBorderSoft).frame(height: 1).padding(.leading, 46)
                SummaryRow(
                    symbol: "square.grid.2x2",
                    title: count(appCount, "app", "apps"),
                    detail: preview(appNames, total: appCount, none: "No apps")
                )
                Rectangle().fill(Theme.creamBorderSoft).frame(height: 1).padding(.leading, 46)
                SummaryRow(
                    symbol: "clock",
                    title: "Ends \(DurationText.endPhrase(end, now: context.date))",
                    detail: "\(DurationText.long(durationMinutes)) from the moment you confirm"
                )
            }
            .padding(.vertical, 4)
            .background(CardBackground(radius: 12))
        }
    }

    private var warningCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ember)
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("This can't be stopped early.")
                    .font(Theme.sans(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("There is no cancel button. Quitting the app, restarting your Mac or deleting Harbour Control won't end it. If something breaks, an administrator can stop it from Terminal. During the session you can add to the blocklist, never remove.")
                    .font(Theme.sans(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.ember.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.ember.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var sharedCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 13))
                .foregroundStyle(Theme.amber)
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Heads up: shared servers")
                    .font(Theme.sans(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(sharedNetworks, id: \.owner) { network in
                    Text("\(network.owner) runs its services on the same servers, so \(network.sideEffects) may also load slowly or not at all until the timer ends.")
                        .font(Theme.sans(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.amberSoft.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.amber.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var riskyCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.amber)
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Heads up: system services")
                    .font(Theme.sans(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Blocking these may break iCloud, the App Store, Messages or system updates until the timer ends:")
                    .font(Theme.sans(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(riskyDomains.joined(separator: ", "))
                    .font(Theme.mono(size: 11))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.amberSoft.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.amber.opacity(0.35), lineWidth: 1)
                )
        )
    }

    // MARK: Buttons

    private var buttons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button("Not yet", action: onCancel)
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)

                // No Return shortcut on purpose: starting must be a deliberate click.
                Button(action: onConfirm) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Start block")
                    }
                }
                .buttonStyle(GlowButtonStyle(fill: Theme.destructiveButton, glow: Theme.beam, height: 40))
            }
            Text("Next, macOS asks for your administrator password.")
                .font(Theme.sans(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Text helpers

    private func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }

    private func preview(_ names: [String], total: Int, none: String) -> String {
        guard total > 0 else { return none }
        guard !names.isEmpty else { return "" }
        let shown = names.prefix(3).joined(separator: ", ")
        return total > 3 ? "\(shown) and \(total - 3) more" : shown
    }
}

private struct SummaryRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.navy)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.navySoft))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.sans(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(Theme.sans(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Bordered parchment button for the safe choice in a dialog.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietBody(configuration: configuration)
    }

    private struct QuietBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Theme.sans(size: 14, weight: .semibold))
                .foregroundStyle(Theme.navy)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hovering ? Color.white : Color.white.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.creamBorder, lineWidth: 1)
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

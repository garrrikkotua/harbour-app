import SwiftUI

struct ConfirmView: View {
    let durationMinutes: Int
    let domainCount: Int
    let appCount: Int
    let riskyDomains: [String]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var durationText: String {
        let h = durationMinutes / 60
        let m = durationMinutes % 60
        switch (h, m) {
        case (0, let m): return "\(m) minutes"
        case (let h, 0) where h == 1: return "1 hour"
        case (let h, 0): return "\(h) hours"
        case (let h, let m) where h == 1: return "1 hour \(m) minutes"
        case (let h, let m): return "\(h) hours \(m) minutes"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            Text("Start block for \(durationText)?")
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                summaryLine(count: domainCount, singular: "domain", plural: "domains")
                summaryLine(count: appCount, singular: "app", plural: "apps")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Text("You will not be able to cancel until the timer ends.")
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if !riskyDomains.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Heads up")
                            .font(.callout.bold())
                    }
                    Text("Blocking these domains may break macOS services (iCloud, App Store, Messages, system updates):")
                        .font(.caption)
                    Text(riskyDomains.joined(separator: ", "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.orange)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                )
            }

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button("Start Block") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(width: 420)
    }

    private func summaryLine(count: Int, singular: String, plural: String) -> some View {
        HStack {
            Image(systemName: count > 0 ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(count > 0 ? .green : .secondary)
            Text("\(count) \(count == 1 ? singular : plural)")
        }
    }
}

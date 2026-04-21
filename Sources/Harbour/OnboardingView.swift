import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var step = 0

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let body: String
    }
    private let steps: [Step] = [
        Step(id: 0,
             title: "Welcome to Harbour Control",
             body: "A focus app with no off switch. Pick what to block, set a timer, and work until it's over."),
        Step(id: 1,
             title: "Block sites and apps",
             body: "Add domains one at a time or use presets like Social Media and Video. Block Mac apps the same way."),
        Step(id: 2,
             title: "No turning back",
             body: "Once a session starts, it runs until the timer ends. Restarting, quitting, or uninstalling won't cancel it."),
        Step(id: 3,
             title: "One-time permission",
             body: "We'll ask for your password once to install system-level rules. Your password is never stored."),
    ]

    var body: some View {
        ZStack {
            Theme.setupBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 28)

                // Illustration
                Group {
                    switch step {
                    case 0: LighthouseIcon(size: 130)
                    case 1: sitesAndApps
                    case 2: ShipsWheelIcon(size: 110, tint: Theme.navy)
                    default: permissionBadge
                    }
                }
                .frame(height: 150)

                // Title
                Text(steps[step].title)
                    .font(Theme.serif(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .padding(.top, 18)

                // Body
                Text(steps[step].body)
                    .font(Theme.sans(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 380)
                    .padding(.top, 8)
                    .padding(.horizontal, 40)

                Spacer()

                // Dots
                HStack(spacing: 8) {
                    ForEach(steps) { s in
                        Circle()
                            .fill(s.id == step ? Theme.navy : Theme.navy.opacity(0.22))
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut(duration: 0.2), value: step)
                    }
                }
                .padding(.bottom, 14)

                // Buttons
                HStack {
                    Button {
                        onFinish()
                    } label: {
                        Text("Skip")
                            .font(Theme.sans(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(height: 36)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain)
                    .opacity(step == steps.count - 1 ? 0 : 1)

                    Spacer()

                    Button {
                        if step == steps.count - 1 {
                            onFinish()
                        } else {
                            withAnimation(.easeOut(duration: 0.25)) { step += 1 }
                        }
                    } label: {
                        Text(step == steps.count - 1 ? "Get started" : "Next")
                            .font(Theme.sans(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.parchmentWarm)
                            .frame(height: 36)
                            .padding(.horizontal, 22)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Theme.primaryButton)
                            )
                            .shadow(color: Theme.navy.opacity(0.22), radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
            }
        }
        .frame(width: 520, height: 560)
    }

    // MARK: Step-specific illustrations

    private var sitesAndApps: some View {
        HStack(spacing: 18) {
            IconTile(color: Theme.navy, soft: Theme.navySoft) {
                GlobeIcon(size: 38, tint: Theme.navy)
            }
            IconTile(color: Theme.amber, soft: Color(red: 0xf4/255, green: 0xea/255, blue: 0xdb/255)) {
                AppGridIcon(size: 38, tint: Theme.amber)
            }
        }
    }

    private var permissionBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Theme.primaryButton)
                .frame(width: 96, height: 96)
                .shadow(color: Theme.navy.opacity(0.25), radius: 14, y: 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        .blendMode(.overlay)
                )
            Image(systemName: "checkmark")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(Theme.parchmentWarm)
        }
    }
}

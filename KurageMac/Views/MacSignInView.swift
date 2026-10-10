import SwiftUI
import KurageCore

/// Same composition as the iPad welcome page: icon, dotted field, and a bottom capsule.
struct MacSignInView: View {
    let model: AppModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    MacWelcomeBrand(iconSize: min(208, geometry.size.width * 0.54, geometry.size.height * 0.36))
                    Spacer(minLength: 32)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MacWelcomeActions(
                isSigningIn: model.isSigningIn,
                statusNote: model.statusNote,
                authorization: model.deviceAuthorization,
                onConnect: { model.connect { openURL($0) } },
                onCancel: model.cancelConnect
            )
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .background(MacWelcomeBackground())
    }
}

private struct MacWelcomeBrand: View {
    let iconSize: CGFloat

    var body: some View {
        VStack(spacing: 48) {
            Image("WelcomeIcon")
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.23, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 24, y: 16)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Welcome to")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Kurage")
                    .font(.largeTitle.weight(.semibold))
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("welcome-title")
        }
        .padding(.horizontal, 28)
    }
}

private struct MacWelcomeActions: View {
    let isSigningIn: Bool
    let statusNote: StatusNote?
    let authorization: DeviceAuthorization?
    let onConnect: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// iPad `secondarySystemBackground`.
    private var buttonFill: Color {
        colorScheme == .dark
            ? Color(red: 28.0 / 255, green: 28.0 / 255, blue: 30.0 / 255)
            : Color(red: 242.0 / 255, green: 242.0 / 255, blue: 247.0 / 255)
    }

    var body: some View {
        VStack(spacing: 12) {
            if let statusNote {
                Text(statusNote.text)
                    .font(.footnote)
                    .foregroundStyle(statusNote.tone == .failure ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("sign-in-status")
            }

            if let authorization {
                Text(authorization.userCode)
                    .font(.title3.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("device-user-code")
                Link("Open authorization page", destination: authorization.verificationURL)
                    .font(.footnote)
            }

            Button(action: onConnect) {
                HStack(spacing: 10) {
                    if isSigningIn { ProgressView().controlSize(.small) }
                    Text(isSigningIn ? "Connecting…" : "Get Started")
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(buttonFill, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(isSigningIn)
            .accessibilityIdentifier("sign-in-button")

            Button("Cancel", role: .cancel, action: onCancel)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .opacity(isSigningIn ? 1 : 0)
                .allowsHitTesting(isSigningIn)
                .accessibilityHidden(!isSigningIn)
                .accessibilityIdentifier("cancel-sign-in")
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }
}

private struct MacWelcomeBackground: View {
    var body: some View {
        Canvas { context, size in
            var dots = Path()
            for x in stride(from: 16.0, through: size.width, by: 27) {
                for y in stride(from: 16.0, through: size.height, by: 27) {
                    dots.addEllipse(in: CGRect(x: x, y: y, width: 3, height: 3))
                }
            }
            context.fill(dots, with: .color(.secondary.opacity(0.15)))
        }
        .background {
            RadialGradient(
                colors: [Color.secondary.opacity(0.1), .clear],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0,
                endRadius: 360
            )
            .background(Color("LaunchBackground"))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

#Preview("Light") {
    MacSignInView(model: AppModel(client: FixtureLodyClient()))
        .frame(width: 1120, height: 760)
}

#Preview("Dark") {
    MacSignInView(model: AppModel(client: FixtureLodyClient()))
        .frame(width: 1120, height: 760)
        .preferredColorScheme(.dark)
}

import SwiftUI
import KurageCore

struct SignInView: View {
    let model: AppModel
    @State private var authorizationPage: AuthorizationPage?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    WelcomeBrand(iconSize: min(208, geometry.size.width * 0.54, geometry.size.height * 0.36))
                    Spacer(minLength: 32)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WelcomeActions(
                isSigningIn: model.isSigningIn,
                statusNote: model.statusNote,
                onConnect: {
                    model.connect { authorizationPage = AuthorizationPage(url: $0) }
                },
                onCancel: model.cancelConnect
            )
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .background(WelcomeBackground())
        .sheet(item: $authorizationPage, onDismiss: {
            if !model.isSignedIn { model.cancelConnect() }
        }) { page in
            AuthorizationBrowser(url: page.url)
                .ignoresSafeArea()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .onChange(of: model.deviceAuthorization) { _, authorization in
            if authorization == nil { authorizationPage = nil }
        }
    }
}

private struct AuthorizationPage: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct WelcomeBrand: View {
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

private struct WelcomeActions: View {
    let isSigningIn: Bool
    let statusNote: StatusNote?
    let onConnect: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let statusNote {
                Text(statusNote.text)
                    .font(.footnote)
                    .foregroundStyle(statusNote.tone == .failure ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("sign-in-status")
            }

            Button(action: onConnect) {
                HStack(spacing: 10) {
                    if isSigningIn { ProgressView() }
                    Text(isSigningIn ? "Connecting…" : "Get Started")
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color(.secondarySystemBackground), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
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

private struct WelcomeBackground: View {
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
    SignInView(model: AppModel(client: FixtureLodyClient()))
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SignInView(model: AppModel(client: FixtureLodyClient()))
        .preferredColorScheme(.dark)
}

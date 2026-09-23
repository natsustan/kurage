import SwiftUI

struct SignInView: View {
    let model: AppModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            SignInTitle()
            if let authorization = model.deviceAuthorization {
                DeviceCodeCard(
                    userCode: authorization.userCode,
                    onReopen: { model.reopenAuthorization { openURL($0) } },
                    onCancel: model.cancelConnect
                )
            } else {
                ConnectForm(
                    isSigningIn: model.isSigningIn,
                    statusNote: model.statusNote,
                    onConnect: { model.connect { openURL($0) } }
                )
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

private struct SignInTitle: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("kurage")
                .font(.largeTitle.weight(.semibold))
            Text("See running sessions when you step away.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct ConnectForm: View {
    let isSigningIn: Bool
    let statusNote: StatusNote?
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onConnect) {
                if isSigningIn {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Connect Lody Cloud")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSigningIn)
            .accessibilityIdentifier("sign-in-button")

            Text("Sign-in happens on Lody's authorization page.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let statusNote {
                Text(statusNote.text)
                    .font(.footnote)
                    .foregroundStyle(statusNote.tone == .failure ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct DeviceCodeCard: View {
    let userCode: String
    let onReopen: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Check this code on the authorization page")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(userCode)
                .font(.title.monospaced().weight(.semibold))
                .textSelection(.enabled)
                .accessibilityIdentifier("device-code")
            Button("Reopen the authorization page", action: onReopen)
                .accessibilityIdentifier("reopen-auth")
            ProgressView()
            Text("Waiting for the browser to confirm…")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Cancel", role: .cancel, action: onCancel)
                .accessibilityIdentifier("cancel-sign-in")
        }
    }
}

#Preview {
    SignInView(model: AppModel(client: FixtureLodyClient()))
}

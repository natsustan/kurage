import SwiftUI
import KurageCore

struct HapticsSettingsView: View {
    @AppStorage(AppHaptics.storageKey) private var hapticsEnabled = true
    @AppStorage(AppAccent.storageKey) private var accent: AppAccent = .black

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Haptics Feedback", isOn: $hapticsEnabled)
                    .tint(accent.color)
                    .padding(18)
                    .background(SettingsPalette.groupBackground, in: .rect(cornerRadius: 20))
                    .accessibilityIdentifier("haptics-toggle")
                Text("Play subtle vibrations when adjusting agent settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(SettingsPalette.background)
        .navigationTitle("Haptics")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("haptics-settings")
    }
}

#Preview {
    NavigationStack {
        HapticsSettingsView()
    }
}

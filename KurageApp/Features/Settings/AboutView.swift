import SwiftUI
import KurageCore

struct AboutView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Build", value: build)
            }
            .listRowBackground(SettingsPalette.groupBackground)
            Section {
                Text("Kurage is an independent third-party iOS client for Lody.")
                Text("Your account, workspaces, and conversations are provided by Lody.")
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(SettingsPalette.groupBackground)
        }
        .scrollContentBackground(.hidden)
        .background(SettingsPalette.background)
        .navigationTitle("About Kurage")
        .navigationBarTitleDisplayMode(.inline)
    }
}

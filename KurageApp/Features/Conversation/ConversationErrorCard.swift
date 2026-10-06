import SwiftUI
import UIKit

struct ConversationErrorCard: View {
    let turnID: String
    let error: ConversationError
    @State private var showsDetails = false
    @State private var copied = false
    @ScaledMetric(relativeTo: .subheadline) private var statusIconWidth = 20.0
    @ScaledMetric(relativeTo: .caption) private var actionIconWidth = 18.0
    @ScaledMetric(relativeTo: .caption) private var chevronWidth = 12.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "xmark.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(statusIconWidth, 28), height: min(statusIconWidth, 28))
                    .alignmentGuide(.firstTextBaseline) { $0.height * 0.8 }
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(error.title)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                if let message = error.readableMessage, message != String(localized: error.title) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    detailsButton
                    Spacer(minLength: 0)
                    copyButton
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.leading, min(statusIconWidth, 28) + 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation-error-\(turnID)-\(error.id)")
        .onChange(of: error) { copied = false }
        .sheet(isPresented: $showsDetails) {
            ConversationErrorDetails(error: error)
        }
    }

    private var detailsButton: some View {
        Button { showsDetails = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Error details")
                    .fixedSize(horizontal: false, vertical: true)
                Image("disclosure-right")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(chevronWidth, 18), height: min(chevronWidth, 18))
                    .alignmentGuide(.firstTextBaseline) { $0.height * 0.8 }
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("error-details-\(turnID)-\(error.id)")
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = error.report
            copied = true
        } label: {
            Label {
                Text(copied ? "Copied" : "Copy error")
            } icon: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(actionIconWidth, 26), height: min(actionIconWidth, 26))
            }
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("copy-error-\(turnID)-\(error.id)")
    }
}

private struct ConversationErrorDetails: View {
    let error: ConversationError
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(error.report)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .accessibilityIdentifier("conversation-error-details")
            .navigationTitle("Error details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("close-error-details")
                }
            }
        }
    }
}

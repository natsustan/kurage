import SwiftUI
import UIKit
import KurageCore

struct ConversationErrorCard: View {
    let turnID: String
    let error: ConversationError
    @State private var showsDetails = false
    @State private var copied = false
    @Environment(\.colorScheme) private var colorScheme
    private static let errorTint = Color(red: 244 / 255, green: 108 / 255, blue: 32 / 255)
    private static let errorBackground = Color(red: 254 / 255, green: 248 / 255, blue: 243 / 255)
    private static let errorBorder = Color(red: 227 / 255, green: 202 / 255, blue: 189 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { showsDetails = true } label: {
                Group {
                    if let message = error.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                        Text(message)
                    } else {
                        Text(error.title)
                    }
                }
                .font(.body)
                .foregroundStyle(Self.errorTint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .padding(12)
                .background(colorScheme == .dark ? Self.errorTint.opacity(0.08) : Self.errorBackground,
                            in: .rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(colorScheme == .dark ? Self.errorBorder.opacity(0.35) : Self.errorBorder,
                                      lineWidth: 1)
                }
            }
            .accessibilityLabel(error.title)
            .accessibilityValue(error.message ?? "")
            .accessibilityHint("View error details")
            .accessibilityIdentifier("error-details-\(turnID)-\(error.id)")
            .accessibilityAction(named: Text("Copy error")) { copyError() }
            .contextMenu {
                Button { copyError() } label: {
                    Label(copied ? "Copied" : "Copy error", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .accessibilityIdentifier("copy-error-\(turnID)-\(error.id)")
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation-error-\(turnID)-\(error.id)")
        .onChange(of: error) { copied = false }
        .sheet(isPresented: $showsDetails) {
            ConversationErrorDetails(error: error, copyIdentifier: "copy-error-\(turnID)-\(error.id)", copied: $copied)
        }
    }

    private func copyError() {
        UIPasteboard.general.string = error.report
        copied = true
    }
}

private struct ConversationErrorDetails: View {
    let error: ConversationError
    let copyIdentifier: String
    @Binding var copied: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var detent: PresentationDetent = .medium

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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = error.report
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy error", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityIdentifier(copyIdentifier)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("close-error-details")
                }
            }
        }
        .presentationBackground(Color(uiColor: .systemBackground))
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }
}

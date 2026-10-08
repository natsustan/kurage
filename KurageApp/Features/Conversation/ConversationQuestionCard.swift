import SwiftUI
import KurageCore

/// Drafts belong to the request identity; streaming updates never replace them.
struct ConversationQuestionCard: View {
    let request: ConversationQuestionRequest
    let isReady: Bool
    let onRespond: @MainActor ([String: QuestionAnswer]?) async throws -> Void

    @State private var drafts: [String: QuestionDraft] = [:]
    @State private var page = 0
    @State private var contentHeight: CGFloat = 160
    @State private var submission: Submission?
    @State private var attempt = 0
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var completed = false
    @FocusState private var inputFocused: Bool

    private struct Submission {
        let answers: [String: QuestionAnswer]?
    }
    private struct Attempt: Equatable {
        let number: Int
        let ready: Bool
    }

    private var question: ConversationQuestion { request.questions[min(page, request.questions.count - 1)] }
    private var draft: Binding<QuestionDraft> {
        Binding(get: { drafts[question.id] ?? QuestionDraft() }, set: { drafts[question.id] = $0 })
    }
    private var answers: [String: QuestionAnswer]? {
        var result: [String: QuestionAnswer] = [:]
        for question in request.questions {
            let draft = drafts[question.id] ?? QuestionDraft()
            guard let answer = draft.answer(for: question) else { return nil }
            result[question.id] = answer
            if let note = question.note, !draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result[note.fieldId] = .text(draft.note)
            }
        }
        return result
    }

    var body: some View {
        if !completed, !request.questions.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let expired = request.autoResolveAt.map { context.date.timeIntervalSince1970 * 1000 >= $0 } ?? false
                let disabled = !isReady || isSubmitting || expired
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Question", systemImage: "questionmark.bubble")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if request.questions.count > 1 {
                            Text("\(page + 1) / \(request.questions.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Button { submit(nil) } label: {
                            Image(systemName: "xmark").frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Skip question")
                        .accessibilityIdentifier("question-close")
                        .disabled(disabled || submission != nil || request.skipOptionID == nil)
                    }
                    ScrollView {
                        QuestionFields(question: question, draft: draft, inputFocused: $inputFocused)
                            .padding(.bottom, 2)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                    }
                    .frame(height: min(contentHeight, 240))
                    .scrollBounceBehavior(.basedOnSize)
                    .disabled(disabled || submission != nil)
                    if let deadline = request.autoResolveAt {
                        Text(expired ? "Continuing…" : "Continues in \(max(0, Int(ceil(deadline / 1000 - context.date.timeIntervalSince1970))))s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                            .accessibilityIdentifier("question-error")
                    }
                    HStack(spacing: 10) {
                        if page > 0 {
                            Button { inputFocused = false; page -= 1 } label: {
                                Image(systemName: "chevron.left")
                            }
                            .accessibilityLabel("Previous question")
                            .accessibilityIdentifier("question-previous")
                        }
                        Spacer(minLength: 0)
                        if isSubmitting { ProgressView().accessibilityLabel("Sending answer") }
                        Button("Skip") { submit(nil) }
                            .buttonStyle(.bordered)
                            .disabled(disabled || submission != nil || request.skipOptionID == nil)
                            .accessibilityIdentifier("question-skip")
                        if submission != nil && !isSubmitting {
                            Button("Retry") { attempt += 1 }
                                .buttonStyle(.borderedProminent)
                                .disabled(disabled)
                                .accessibilityIdentifier("question-retry")
                        } else if page < request.questions.count - 1 {
                            Button("Next") { inputFocused = false; page += 1 }
                                .buttonStyle(.borderedProminent)
                                .disabled(disabled || draft.wrappedValue.answer(for: question) == nil)
                                .accessibilityIdentifier("question-next")
                        } else {
                            Button("Send") { if let answers { submit(answers) } }
                                .buttonStyle(.borderedProminent)
                                .disabled(disabled || answers == nil || request.answerOptionID == nil)
                                .accessibilityIdentifier("question-send")
                        }
                    }
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
                .padding(18)
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("question-card")
            }
            .task(id: Attempt(number: attempt, ready: isReady)) {
                guard attempt > 0, isReady, let submission else { return }
                isSubmitting = true
                error = nil
                defer { isSubmitting = false }
                do {
                    try await onRespond(submission.answers)
                    try Task.checkCancellation()
                    completed = true
                } catch is CancellationError {
                    // Retain the exact submitted payload if delivery was interrupted.
                } catch LodyClientError.permissionMissing {
                    error = "This question has already ended. Refresh the conversation."
                } catch {
                    self.error = "Could not confirm the answer. Retry to check or send it again."
                }
            }
        }
    }

    private func submit(_ answers: [String: QuestionAnswer]?) {
        guard submission == nil else { return }
        inputFocused = false
        submission = Submission(answers: answers)
        attempt += 1
    }
}

private struct QuestionFields: View {
    @AppStorage(AppAccent.storageKey) private var accent: AppAccent = .black
    let question: ConversationQuestion
    @Binding var draft: QuestionDraft
    var inputFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.question).font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("question-prompt")
            ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                Button {
                    draft.text = ""
                    if question.multiSelect {
                        if draft.selected.contains(option.label) { draft.selected.removeAll { $0 == option.label } }
                        else { draft.selected.append(option.label) }
                    } else { draft.selected = [option.label] }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: draft.selected.contains(option.label) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(draft.selected.contains(option.label) ? accent.color : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.label).foregroundStyle(.primary)
                            if let description = option.description {
                                Text(description).font(.footnote).foregroundStyle(.secondary)
                            }
                            if let preview = option.preview {
                                Text(preview).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(draft.selected.contains(option.label) ? .isSelected : [])
            }
            if question.allowCustomAnswer {
                if question.isSecret {
                    SecureField("Reply…", text: $draft.text)
                        .textContentType(.password)
                        .focused(inputFocused)
                        .accessibilityIdentifier("question-reply")
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("Reply…", text: $draft.text, axis: .vertical)
                        .lineLimit(2...5)
                        .focused(inputFocused)
                        .padding(12)
                        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 14))
                        .accessibilityIdentifier("question-reply")
                }
            }
            if let note = question.note {
                if let description = note.description { Text(description).font(.footnote).foregroundStyle(.secondary) }
                if note.isSecret == true {
                    SecureField(note.title ?? "Additional note", text: $draft.note)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField(note.title ?? "Additional note", text: $draft.note, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .onChange(of: draft.text) { _, text in
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.selected = [] }
        }
    }
}

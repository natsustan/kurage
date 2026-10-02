import SwiftUI

/// The run configuration shown in the composer: a summary plus the pickers the
/// agent allows for the next turn.
struct RunConfigMenu: Equatable {
    struct Section: Identifiable, Equatable {
        enum Kind: String {
            case provider
            case model
            case reasoning

            var title: String {
                switch self {
                case .provider: "Provider"
                case .model: "Model"
                case .reasoning: "Reasoning"
                }
            }
        }

        var kind: Kind
        let options: [SessionRunConfig.Value]
        var selection: String
        var id: Kind { kind }

        init(kind: Kind, options: [SessionRunConfig.Value], selection: String) {
            self.kind = kind
            self.selection = selection
            // Capabilities describe the allowed values, not their intensity order.
            // Keep unfamiliar values in their original slots instead of guessing.
            if kind == .reasoning {
                let ranked = options.compactMap { option -> (SessionRunConfig.Value, Int)? in
                    guard let rank = Self.reasoningRank(option.value) ?? Self.reasoningRank(option.label) else { return nil }
                    return (option, rank)
                }
                var ordered = ranked.enumerated().sorted {
                    $0.element.1 == $1.element.1 ? $0.offset < $1.offset : $0.element.1 < $1.element.1
                }.map { $0.element.0 }.makeIterator()
                self.options = options.map { option in
                    if (Self.reasoningRank(option.value) ?? Self.reasoningRank(option.label)) != nil {
                        return ordered.next() ?? option
                    }
                    return option
                }
            } else {
                self.options = options
            }
        }

        /// Reserve a visual zero when the provider does not offer an off value.
        /// It is not a selectable protocol option.
        var reasoningZeroOffset: Int {
            guard let first = options.first else { return 0 }
            return (Self.reasoningRank(first.value) ?? Self.reasoningRank(first.label)) == 0 ? 0 : 1
        }

        var reasoningTickCount: Int { options.count + reasoningZeroOffset }

        private static func reasoningRank(_ value: String) -> Int? {
            let key = value.lowercased().filter { $0.isLetter || $0.isNumber }
            switch key {
            case "none", "off", "disabled": return 0
            case "minimal": return 1
            case "low": return 2
            case "medium": return 3
            case "high": return 4
            case "xhigh", "extrahigh": return 5
            case "max", "maximum": return 6
            case "ultra": return 7
            default: return nil
            }
        }
    }

    var modelLabel: String? = nil
    var reasoningLabel: String? = nil
    var providerLabel: String? = nil
    var isLoading = false
    var loadFailed = false

    var reasoningProgress: Double {
        guard let section = sections.first(where: { $0.kind == .reasoning }),
              let index = section.options.firstIndex(where: { $0.value == section.selection }) else { return 1 }
        return Double(index + section.reasoningZeroOffset) / Double(max(1, section.reasoningTickCount - 1))
    }

    var accessibilitySummary: String
    /// Empty when the configuration is read-only.
    var sections: [Section]
}

extension SessionRunConfig {
    /// An existing session offers one editable value; see `Editable`.
    var menu: RunConfigMenu? {
        let parts = [model?.label, reasoning?.label].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        let accessibility = [model.map { "Model \($0.label)" }, reasoning.map { "reasoning \($0.label)" }]
            .compactMap { $0 }.joined(separator: ", ")
        var sections: [RunConfigMenu.Section] = []
        if let editable {
            let isReasoning = editable.kind == .reasoning
            sections.append(RunConfigMenu.Section(
                kind: isReasoning ? .reasoning : .model, options: editable.options,
                selection: (isReasoning ? reasoning : model)?.value ?? ""
            ))
        }
        return RunConfigMenu(
            modelLabel: model?.label, reasoningLabel: reasoning?.label,
            accessibilitySummary: accessibility,
            sections: sections
        )
    }
}

/// Floating input capsule shared by follow-ups and new sessions, with a compact
/// gauge button for the next turn's configuration.
struct SessionComposer: View {
    struct Identifiers {
        var container: String
        var field: String
        var send: String

        static let followUp = Identifiers(container: "follow-up-composer", field: "follow-up-field", send: "send-follow-up")
    }

    @Binding var draft: String
    @Binding var mentions: ComposerMentionState
    @Binding var attachments: [ComposerAttachment]
    @State private var pendingAttachments: [PendingComposerAttachment] = []
    private var isLoadingAttachments: Bool { !pendingAttachments.isEmpty }
    @State private var attachmentError: String?
    let isSending: Bool
    var allowsEditingWhileSending = false
    private var blocksEditing: Bool { isSending && !allowsEditingWhileSending }
    let isCancelling: Bool
    let isSessionRunning: Bool
    let supportsTextSending: Bool
    let supportsTextSendingWhileRunning: Bool
    let supportsSessionCancellation: Bool
    let runConfig: RunConfigMenu?
    var contextWindowUsage: ContextWindowUsage? = nil
    var placeholder: LocalizedStringResource = "Send a follow-up"
    var identifiers: Identifiers = .followUp
    /// Blocks sending while prerequisites load, without blocking typing.
    var canSubmit = true
    var focusesOnAppear = false
    var dismissFocus = false
    var mentionSourceID = ""
    var loadMentionSessions: (@MainActor () async throws -> [MentionSession])? = nil
    var loadMentionSkills: (@MainActor () async throws -> [MentionSkill])? = nil
    let onSend: () -> Void
    let onCancel: () -> Void
    let onChooseRunConfig: (RunConfigMenu.Section.Kind, String) -> Void
    @ScaledMetric(relativeTo: .body) private var mentionRowHeight = 64
    @ScaledMetric(relativeTo: .body) private var mentionIconWidth = 24
    @State private var isFocused = false
    @State private var selection: TextSelection?
    @State private var selectionRequest: MentionEditor.SelectionRequest?
    @State private var mentionSessions: [MentionSession] = []
    @State private var mentionSkills: [MentionSkill] = []
    @State private var sessionsLoaded = false
    @State private var skillsLoaded = false
    @State private var mentionLoadFailed = false
    @State private var mentionRetry = 0
    @State private var loadedMentionSourceID = ""
    @State private var showsRunConfig = false
    @State private var showsAdvanced = false
    @State private var gaugeProgress: Double?
    @State private var targetGaugeProgress = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    private var editableDraft: Binding<String> {
        Binding(
            get: { draft },
            set: { value in
                guard !blocksEditing else { return }
                mentions.reconcile(draft)
                let edit = mentions.edit(value)
                draft = edit.text
                if let caret = edit.caret {
                    selection = TextSelection(insertionPoint: String.Index(utf16Offset: caret, in: edit.text))
                    selectionRequest = .init(caret: caret)
                }
            }
        )
    }

    private var hasInput: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !attachments.isEmpty || isLoadingAttachments
    }

    private var showsSend: Bool {
        supportsTextSending && (!isSessionRunning || supportsTextSendingWhileRunning && (hasInput || isSending))
    }

    private var canSend: Bool {
        showsSend && canSubmit && !isSending && !isCancelling &&
            (!mentions.hasSkillMentions || loadedMentionSourceID == mentionSourceID && skillsLoaded) &&
            !isLoadingAttachments && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    private var mentionQuery: ComposerMentionQuery? {
        guard isFocused, let query = ComposerMentionQuery.active(in: draft, selection: selection) else { return nil }
        let start = query.range.lowerBound.utf16Offset(in: draft)
        let end = query.range.upperBound.utf16Offset(in: draft)
        guard !mentions.ranges.contains(where: { $0.start < end && $0.end > start }) else { return nil }
        return query
    }

    private var mentionLoadID: String? {
        // Leaving the foreground cancels pending bridge requests.
        guard scenePhase == .active else { return nil }
        // Prefetch both sources on focus. Typing a trigger or moving between
        // @ and $ then filters locally without cancelling and restarting reads.
        return "\(mentionSourceID)|\(isFocused || mentions.hasSkillMentions)|\(mentionRetry)"
    }

    var body: some View {
        let loadID = mentionLoadID
        VStack(spacing: 8) {
            if let query = mentionQuery {
                mentionMenu(query)
            } else if mentions.hasSkillMentions, mentionLoadFailed {
                Button("Could not refresh skills. Retry") { mentionRetry += 1 }
                    .accessibilityIdentifier("mention-retry")
            }
            VStack(spacing: 0) {
                if !attachments.isEmpty || isLoadingAttachments {
                    ComposerAttachmentStrip(attachments: $attachments, pending: pendingAttachments, disabled: blocksEditing)
                }
                ZStack(alignment: .topLeading) {
                    MentionEditor(text: editableDraft, selection: $selection,
                                  isFocused: $isFocused,
                                  selectionRequest: selectionRequest,
                                  ranges: mentions.ranges, isEnabled: !blocksEditing, identifier: identifiers.field,
                                  accessibilityLabel: placeholder)
                    if draft.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                actionRow
            }
            .padding(8)
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifiers.container)
        }
            .alert("Attachment unavailable", isPresented: Binding(
                get: { attachmentError != nil },
                set: { if !$0 { attachmentError = nil } }
            )) {
                Button("OK", role: .cancel) { attachmentError = nil }
            } message: { Text(attachmentError ?? "") }
            .onAppear {
                targetGaugeProgress = runConfig?.reasoningProgress ?? 1
                gaugeProgress = targetGaugeProgress
                if focusesOnAppear && !dismissFocus { isFocused = true }
            }
            .onChange(of: dismissFocus) { _, shouldDismiss in
                if shouldDismiss { isFocused = false }
            }
            .onChange(of: runConfig?.reasoningProgress) { _, progress in
                targetGaugeProgress = progress ?? 1
                if !showsRunConfig && !showsAdvanced { updateGauge() }
            }
            .onChange(of: showsRunConfig) { _, isPresented in
                if !isPresented && !showsAdvanced { updateGauge() }
            }
            .background {
                RunConfigOverlayAnchor(isPresented: showsRunConfig, runConfig: runConfig,
                                       onChoose: onChooseRunConfig,
                                       onDismiss: {
                                           showsRunConfig = false
                                       },
                                       onAdvanced: {
                                           showsRunConfig = false
                                           showsAdvanced = true
                                       })
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { showsRunConfig = false }
            }
            .onChange(of: draft) { _, text in mentions.reconcile(text) }
            .task(id: loadID) { await loadMentions(for: loadID) }
            .sheet(isPresented: $showsAdvanced, onDismiss: updateGauge) {
                RunConfigAdvanced(runConfig: runConfig, onChoose: onChooseRunConfig)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .onAppear { isFocused = false }
            }
    }

    private func loadMentions(for loadID: String?) async {
        guard loadID == mentionLoadID, scenePhase == .active, !Task.isCancelled else { return }
        if loadedMentionSourceID != mentionSourceID {
            mentionSessions = []
            mentionSkills = []
            sessionsLoaded = false
            skillsLoaded = false
            loadedMentionSourceID = mentionSourceID
        }
        // A draft that already carries skill mentions reloads them even with the
        // menu closed: switching projects changes the skills it can point at.
        guard isFocused || mentions.hasSkillMentions else { return }
        mentionLoadFailed = false
        let sourceID = mentionSourceID
        async let sessions: Void = loadSessions(sourceID: sourceID)
        async let skills: Void = loadSkills(sourceID: sourceID)
        _ = await (sessions, skills)
    }

    private func loadSessions(sourceID: String) async {
        if !sessionsLoaded, let loadMentionSessions {
            do {
                let loaded = try await loadMentionSessions()
                try Task.checkCancellation()
                guard loadedMentionSourceID == sourceID else { return }
                mentionSessions = loaded
                sessionsLoaded = true
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                mentionLoadFailed = true
            }
        }
    }

    private func loadSkills(sourceID: String) async {
        if !skillsLoaded, let loadMentionSkills {
            do {
                let loaded = try await loadMentionSkills()
                try Task.checkCancellation()
                guard loadedMentionSourceID == sourceID else { return }
                mentionSkills = loaded
                skillsLoaded = true
                if let rewritten = mentions.resolveSkills(loaded, in: draft) { draft = rewritten }
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                mentionLoadFailed = true
            }
        }
    }

    private func mentionMenu(_ query: ComposerMentionQuery) -> some View {
        let term = query.term.lowercased()
        let sessions = query.trigger == .combined ? mentionSessions.filter {
            term.isEmpty || $0.title.localizedStandardContains(term)
        }.prefix(25) : []
        let skills = mentionSkills.filter {
            term.isEmpty || $0.token.localizedStandardContains(term) ||
                $0.name.localizedStandardContains(term) || $0.description.localizedStandardContains(term)
        }.prefix(25)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sessions) { session in
                    Button { chooseSession(session, query: query) } label: {
                        mentionRow(icon: "bubble.left.and.text.bubble.right", title: session.title,
                                   subtitle: "Session", detail: nil)
                    }
                    .accessibilityIdentifier("mention-session-\(session.id)")
                }
                ForEach(skills) { skill in
                    Button { chooseSkill(skill, query: query) } label: {
                        mentionRow(icon: "sparkles", title: skill.name,
                                   subtitle: "Skill", detail: skill.description)
                    }
                    .accessibilityIdentifier("mention-skill-\(skill.token)")
                }
                if mentionLoadFailed && (!sessions.isEmpty || !skills.isEmpty) {
                    Button("Some suggestions unavailable. Retry") { mentionRetry += 1 }
                        .padding(16)
                        .accessibilityIdentifier("mention-retry")
                }
                if sessions.isEmpty && skills.isEmpty {
                    if mentionLoadFailed {
                        Button("Could not load suggestions. Retry") { mentionRetry += 1 }
                            .padding(16)
                            .accessibilityIdentifier("mention-retry")
                    } else if !skillsLoaded || query.trigger == .combined && !sessionsLoaded {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading suggestions").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: mentionRowHeight, alignment: .leading)
                        .padding(.horizontal, 14)
                    } else {
                        Text("No matches")
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        // Large accessibility text also grows the multiline composer. Reserve
        // one candidate row so it stays reachable above the keyboard; the rest
        // remain scrollable. Loading and results use the same viewport.
        .frame(maxWidth: .infinity)
        .frame(height: mentionRowHeight * (dynamicTypeSize.isAccessibilitySize ? 1 : 3))
        .clipped()
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .buttonStyle(.plain)
        .accessibilityIdentifier("mention-suggestions")
    }

    private func mentionRow(icon: String, title: String, subtitle: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: mentionIconWidth)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body).lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: mentionRowHeight)
        .contentShape(Rectangle())
    }

    private func chooseSession(_ session: MentionSession, query: ComposerMentionQuery) {
        let base = session.title.split(whereSeparator: \.isWhitespace).joined(separator: "-")
        let slug = String((base.isEmpty ? session.id : base).prefix(40))
        let token = "@\(slug)"
        insertMention(token, kind: .session(id: session.id, title: session.title), query: query)
    }

    private func chooseSkill(_ skill: MentionSkill, query: ComposerMentionQuery) {
        insertMention("$\(skill.token)", kind: .skill(token: skill.token, path: skill.path), query: query)
    }

    private func insertMention(_ token: String, kind: ComposerMentionState.Kind, query: ComposerMentionQuery) {
        let (text, caretOffset) = mentions.insert(token, kind: kind, replacing: query.range, in: draft)
        draft = text
        selection = TextSelection(insertionPoint: String.Index(utf16Offset: caretOffset, in: text))
        selectionRequest = .init(caret: caretOffset)
        isFocused = true
    }

    private func updateGauge() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) {
            gaugeProgress = targetGaugeProgress
        }
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                ComposerAttachments(attachments: $attachments, pending: $pendingAttachments,
                                    error: $attachmentError, disabled: blocksEditing)
                FullAccessButton()
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if let contextWindowUsage, contextWindowUsage.isValid {
                    ContextWindowButton(usage: contextWindowUsage)
                }
                if let runConfig {
                    Button {
                        showsRunConfig = true
                    } label: {
                        ReasoningGauge(progress: gaugeProgress ?? runConfig.reasoningProgress)
                            .frame(width: 25, height: 25)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(runConfig.accessibilitySummary)
                    .accessibilityHint("Adjust reasoning or open advanced settings")
                    .accessibilityIdentifier("run-config-menu")
                }
            }
            if isSessionRunning && supportsSessionCancellation && !showsSend {
                Button(action: onCancel) {
                    composerIcon("stop.fill", enabled: !isSending && !isCancelling)
                }
                .disabled(isSending || isCancelling)
                .buttonStyle(.plain)
                .accessibilityLabel("Stop reply")
                .accessibilityIdentifier("pause-session")
            }
            if showsSend {
                Button(action: onSend) {
                    composerIcon("arrow.up", enabled: canSend)
                }
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.plain)
                .accessibilityLabel(isSending ? Text("Sending") : Text("Send"))
                .accessibilityIdentifier(identifiers.send)
            }
        }
    }

    private func composerIcon(_ name: String, enabled: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .frame(width: 40, height: 30)
            .background(enabled ? Color.accentColor : Color.primary.opacity(0.08), in: Capsule())
            .frame(width: 48, height: 44)
            .contentShape(Rectangle())
    }
}

private struct FullAccessButton: View {
    @State private var showsDetails = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Button {
            showsDetails = true
        } label: {
            Image("full-access")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(.red)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Permission mode")
        .accessibilityValue("Full access")
        .accessibilityHint("Show current permission mode")
        .accessibilityIdentifier("full-access-mode")
        .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
            Text("Full access")
                .font(.subheadline.weight(.semibold))
                .padding(14)
                .accessibilityIdentifier("full-access-detail")
                .presentationCompactAdaptation(.popover)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { showsDetails = false }
        }
    }
}

private struct ContextWindowButton: View {
    let usage: ContextWindowUsage
    @State private var showsDetails = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Button {
            showsDetails = true
        } label: {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: usage.usedFraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 22, height: 22)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Context window")
        .accessibilityValue("\(compactTokens(usage.used)) used of \(compactTokens(usage.size))")
        .accessibilityHint("Show context window usage")
        .accessibilityIdentifier("context-window-usage")
        .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Context window")
                    .font(.subheadline.weight(.semibold))
                Text("\(compactTokens(usage.used)) used / \(compactTokens(usage.size))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("context-window-detail")
            }
            .padding(14)
            .presentationCompactAdaptation(.popover)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { showsDetails = false }
        }
    }

    private func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 { return "\(Int((Double(value) / 1_000).rounded()))K" }
        return "\(value)"
    }
}

/// Compact first level: model, current effort, and discrete reasoning stops.
private struct RunConfigPanel: View {
    let runConfig: RunConfigMenu
    let onChoose: (RunConfigMenu.Section.Kind, String) -> Void
    let onAdvanced: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Button(action: onAdvanced) {
                HStack(spacing: 6) {
                    Text(runConfig.modelLabel ?? "Model").fontWeight(.semibold)
                    Text(runConfig.reasoningLabel ?? "Default").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.title3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("run-config-advanced")
            if let reasoning = runConfig.sections.first(where: { $0.kind == .reasoning }),
               reasoning.options.count > 1 {
                ReasoningDial(section: reasoning) { onChoose(.reasoning, $0) }
                    .padding(10)
                    // Glass can render this dial invisible in the separate overlay window.
                    .background(.regularMaterial, in: Capsule())
            } else {
                Text("Reasoning is not adjustable for this model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, 30)
    }
}

private struct ReasoningDial: View {
    let section: RunConfigMenu.Section
    let onChoose: (String) -> Void
    @Environment(\.layoutDirection) private var layoutDirection

    private var selectedIndex: Int? {
        section.options.firstIndex { $0.value == section.selection }
    }

    var body: some View {
        GeometryReader { geometry in
            let diameter: CGFloat = 40
            let travel = max(0, geometry.size.width - diameter - 16)
            let step = travel / CGFloat(max(1, section.options.count - 1))
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.06))
                if let selectedIndex {
                    Capsule().fill(Color(uiColor: .label))
                        .frame(width: diameter + 16 + step * CGFloat(selectedIndex))
                }
                HStack(spacing: 0) {
                    ForEach(0..<section.options.count, id: \.self) { tick in
                        if tick > 0 { Spacer(minLength: 0) }
                        Circle()
                            .fill(Color(uiColor: .systemGray))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.horizontal, 28)
                if let selectedIndex {
                    Circle().fill(Color(uiColor: .systemBackground))
                        .frame(width: diameter, height: diameter)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        .padding(.leading, 8 + step * CGFloat(selectedIndex))
                }
            }
            .contentShape(.capsule)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let x = layoutDirection == .rightToLeft
                    ? geometry.size.width - value.location.x : value.location.x
                let index = min(section.options.count - 1, max(0, Int(((x - 28) / max(1, step)).rounded())))
                let option = section.options[index]
                if option.value != section.selection { onChoose(option.value) }
            })
        }
        .frame(height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reasoning")
        .accessibilityValue(section.options.first { $0.value == section.selection }?.label ?? "Default")
        .accessibilityAdjustableAction { direction in
            let current = selectedIndex ?? -1
            let index = direction == .increment ? min(section.options.count - 1, current + 1) : max(0, current - 1)
            onChoose(section.options[index].value)
        }
        .accessibilityIdentifier("reasoning-dial")
        .sensoryFeedback(.selection, trigger: section.selection)
    }
}

private struct RunConfigAdvanced: View {
    let runConfig: RunConfigMenu?
    let onChoose: (RunConfigMenu.Section.Kind, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    configRow(.provider, value: runConfig?.providerLabel)
                    configRow(.model, value: runConfig?.modelLabel)
                    configRow(.reasoning, value: runConfig?.reasoningLabel)
                    if runConfig?.isLoading == true {
                        ProgressView("Loading models…")
                    } else if runConfig?.loadFailed == true {
                        Text("Could not load this provider. Choose it again to retry.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    LabeledContent("Speed", value: "Unavailable")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("run-config-speed")
                } footer: {
                    Text("Fast mode is not supported yet.")
                }
            }
            .navigationTitle("Advanced")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("run-config-done")
                }
            }
        }
    }

    @ViewBuilder
    private func configRow(_ kind: RunConfigMenu.Section.Kind, value: String?) -> some View {
        if let section = runConfig?.sections.first(where: { $0.kind == kind }), !section.options.isEmpty {
            HStack {
                Text(kind.title)
                    .accessibilityIdentifier("run-config-\(kind.rawValue)-label")
                Spacer()
                Menu {
                    ForEach(section.options) { option in
                        Button {
                            onChoose(kind, option.value)
                        } label: {
                            if option.value == section.selection {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(section.options.first { $0.value == section.selection }?.label ?? value ?? "Default")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .tint(Color(uiColor: .label))
                .menuOrder(.fixed)
                .accessibilityIdentifier("run-config-\(kind.rawValue)")
            }
            .foregroundStyle(Color(uiColor: .label))
        } else if let value {
            LabeledContent(kind.title, value: value)
                .foregroundStyle(.secondary)
        }
    }
}

/// A small, graduated dial. The needle and illuminated arc follow the offered
/// reasoning levels rather than assuming every provider has the same scale.
@Animatable
private struct ReasoningGauge: View {
    var progress: Double

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) * 0.46
            let start = 145.0
            let sweep = 250.0
            // Center the visible arc, whose lower ends stop above a full circle's bottom.
            let lowerExtent = sin(start * .pi / 180) * radius
            let center = CGPoint(x: size.width / 2,
                                 y: (size.height + radius - lowerExtent) / 2)
            func point(_ angle: Double, radius: Double) -> CGPoint {
                CGPoint(x: center.x + cos(angle * .pi / 180) * radius,
                        y: center.y + sin(angle * .pi / 180) * radius)
            }
            for tick in 0..<11 {
                let fraction = Double(tick) / 10
                let angle = start + sweep * fraction
                var path = Path()
                path.move(to: point(angle, radius: radius * 0.78))
                path.addLine(to: point(angle, radius: radius))
                let active = fraction <= progress
                context.stroke(path, with: .color(.primary.opacity(active ? 1 : 0.22)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            let angle = start + sweep * progress
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: point(angle, radius: radius * 0.6))
            context.stroke(needle, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 2.4, y: center.y - 2.4, width: 4.8, height: 4.8)),
                         with: .color(.primary))
        }
        .accessibilityHidden(true)
    }
}

/// A scene-local overlay preserves input focus. A transient content snapshot
/// supplies the blurred backdrop; it is released when the overlay closes.
private struct RunConfigOverlayAnchor: UIViewRepresentable {
    let isPresented: Bool
    let runConfig: RunConfigMenu?
    let onChoose: (RunConfigMenu.Section.Kind, String) -> Void
    let onDismiss: () -> Void
    let onAdvanced: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.onLayout = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.update(from: view)
        }
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.configuration = self
        context.coordinator.update(from: view)
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
        view.onLayout = nil
        coordinator.close()
    }

    final class AnchorView: UIView {
        var onLayout: (() -> Void)?
        override func layoutSubviews() { super.layoutSubviews(); onLayout?() }
        override func didMoveToWindow() { super.didMoveToWindow(); onLayout?() }
    }

    final class OverlayWindow: UIWindow {
        override var canBecomeKey: Bool { false }
    }

    @MainActor
    final class Coordinator {
        var configuration: RunConfigOverlayAnchor?
        private var window: OverlayWindow?
        private var backdrop: UIImage?
        private var host: UIHostingController<RunConfigOverlay>?
        private var previousRect: CGRect = .zero
        private var previousConfig: RunConfigMenu?

        func update(from anchor: UIView) {
            guard let configuration, configuration.isPresented,
                  let config = configuration.runConfig,
                  let source = anchor.window, let scene = source.windowScene else {
                close()
                return
            }
            let rect = anchor.convert(anchor.bounds, to: source)
            if backdrop == nil || window?.bounds.size != source.bounds.size {
                backdrop = UIGraphicsImageRenderer(bounds: source.bounds).image { _ in
                    source.drawHierarchy(in: source.bounds, afterScreenUpdates: false)
                }
            }
            let content = RunConfigOverlay(anchor: rect, backdrop: backdrop, runConfig: config,
                                           onChoose: configuration.onChoose,
                                           onDismiss: configuration.onDismiss,
                                           onAdvanced: configuration.onAdvanced)
            if let host, let window {
                window.frame = source.frame
                if rect != previousRect || config != previousConfig { host.rootView = content }
            } else {
                let window = OverlayWindow(windowScene: scene)
                window.frame = source.frame
                window.windowLevel = .alert + 1
                window.backgroundColor = .clear
                window.overrideUserInterfaceStyle = source.traitCollection.userInterfaceStyle
                let host = UIHostingController(rootView: content)
                host.view.backgroundColor = .clear
                host.view.accessibilityViewIsModal = true
                window.rootViewController = host
                self.host = host
                self.window = window
                window.isHidden = false
            }
            previousRect = rect
            previousConfig = config
        }

        func close() {
            window?.isHidden = true
            window?.rootViewController = nil
            host = nil
            window = nil
            backdrop = nil
            previousConfig = nil
        }
    }
}

private struct RunConfigOverlay: View {
    let anchor: CGRect
    let backdrop: UIImage?
    let runConfig: RunConfigMenu
    let onChoose: (RunConfigMenu.Section.Kind, String) -> Void
    let onDismiss: () -> Void
    let onAdvanced: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Group {
                    if reduceTransparency {
                        Color(uiColor: .systemBackground)
                    } else if let backdrop {
                        Image(uiImage: backdrop)
                            .resizable()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 8)
                    }
                }
                    .mask {
                        let height = max(1, geometry.size.height)
                        let start = max(0, anchor.minY - 180) / height
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                                               .init(color: .clear, location: start),
                                               .init(color: .black, location: min(1, start + 150 / height)),
                                               .init(color: .black, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .overlay { Color.clear.contentShape(.rect).onTapGesture(perform: onDismiss) }
                    .accessibilityLabel("Dismiss model settings")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onDismiss() }
                    .accessibilityIdentifier("run-config-dismiss")
                RunConfigPanel(runConfig: runConfig, onChoose: onChoose, onAdvanced: onAdvanced)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, geometry.size.height - anchor.maxY))
                    .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
        .accessibilityAction(.escape, onDismiss)
    }
}

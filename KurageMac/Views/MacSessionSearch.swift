import AppKit
import SwiftUI
import KurageCore

struct MacSessionSearchOverlay: View {
    let model: AppModel
    @Bindable var window: MacWindowState

    var body: some View {
        GeometryReader { geo in
            let width = min(860, max(320, geo.size.width - 56))
            ZStack(alignment: .top) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                MacSessionSearchPanel(model: model, window: window, onClose: close)
                    .frame(width: width)
                    .padding(.top, MacSessionSearchMetrics.topInset)
            }
        }
    }

    private func close() {
        model.stopSessionSearch()
        window.showsSessionSearch = false
    }
}

private struct MacSessionSearchPanel: View {
    let model: AppModel
    @Bindable var window: MacWindowState
    let onClose: () -> Void
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hits: [SessionSearchHit] {
        let query = trimmedQuery
        guard !query.isEmpty else { return [] }
        return model.sessions.compactMap { session in
            if let result = SessionSearch.result(
                title: session.title,
                body: model.sessionSearchBody(sessionID: session.id),
                query: query
            ) {
                return SessionSearchHit(session: session, snippet: result.snippet)
            }
            let matchesContext = session.preview.localizedStandardContains(query)
                || session.projectName?.localizedStandardContains(query) == true
            return matchesContext ? SessionSearchHit(session: session, snippet: nil) : nil
        }
    }

    var body: some View {
        // Matching observes the query and indexed bodies, independently of result navigation.
        MacSessionSearchContent(model: model, window: window, query: $query, hits: hits, onClose: onClose)
            .task(id: !trimmedQuery.isEmpty) {
                if trimmedQuery.isEmpty {
                    model.stopSessionSearch()
                } else {
                    await model.indexSessionsForSearch()
                }
            }
            .onDisappear { model.stopSessionSearch() }
    }
}

private struct MacSessionSearchContent: View {
    let model: AppModel
    let window: MacWindowState
    @Binding var query: String
    let hits: [SessionSearchHit]
    let onClose: () -> Void
    @State private var selection: SessionSummary.ID?
    @State private var scrollRequest: SessionSearchScrollRequest?
    @State private var keyboardPointerLocation: NSPoint?
    @FocusState private var queryFocused: Bool

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: MacSessionSearchMetrics.fieldSize))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search sessions", text: $query)
                    .font(.system(size: MacSessionSearchMetrics.fieldSize))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($queryFocused)
                    .accessibilityIdentifier("session-search-field")
                    .onSubmit { openSelection(in: hits) }
                    .onKeyPress(.upArrow) { moveSelection(-1, in: hits); return .handled }
                    .onKeyPress(.downArrow) { moveSelection(1, in: hits); return .handled }
                    .onKeyPress(.escape) { onClose(); return .handled }
                if model.isIndexingSessionSearch && hasQuery {
                    ProgressView()
                        .controlSize(.regular)
                        .accessibilityLabel("Searching messages")
                }
                if !query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") {
                        query = ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.system(size: MacSessionSearchMetrics.secondarySize))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("clear-session-search")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            if hasQuery {
                Divider()
                FittingScroll(maxHeight: 440, scrollRequest: scrollRequest) {
                    resultList(hits)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: MacSessionSearchMetrics.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: MacSessionSearchMetrics.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 28, y: 12)
        .overlay {
            RoundedRectangle(cornerRadius: MacSessionSearchMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session-search-panel")
        .onAppear { selection = hits.first?.id }
        .onChange(of: hits.map(\.id)) { _, ids in
            if let selection, ids.contains(selection) { return }
            self.selection = ids.first
        }
        .onExitCommand(perform: onClose)
        .task { queryFocused = true }
    }

    private func resultList(_ hits: [SessionSearchHit]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sessions")
                .font(.system(size: MacSessionSearchMetrics.secondarySize))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .accessibilityIdentifier("session-search-heading")
            if model.sessions.isEmpty {
                status("No sessions", identifier: "session-search-empty")
            } else if hits.isEmpty && model.isIndexingSessionSearch {
                status("Searching messages…", identifier: "session-search-indexing")
            } else if hits.isEmpty {
                status("No matching sessions", identifier: "session-search-empty")
                if model.hasIncompleteSessionSearch {
                    Button("Search incomplete. Retry") {
                        Task { await model.indexSessionsForSearch() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(model.isIndexingSessionSearch)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("retry-session-search")
                }
            } else {
                ForEach(hits) { hit in
                    resultRow(hit)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func status(_ title: String, identifier: String) -> some View {
        Text(title)
            .font(.system(size: MacSessionSearchMetrics.titleSize))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .accessibilityIdentifier(identifier)
    }

    private func resultRow(_ hit: SessionSearchHit) -> some View {
        let selected = selection == hit.id
        return Button {
            selection = hit.id
            open(hit.session)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.session.title)
                        .font(.system(size: MacSessionSearchMetrics.titleSize))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                    if let snippet = hit.snippet {
                        Text(snippet)
                            .font(.system(size: MacSessionSearchMetrics.secondarySize))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 12)
                Text("Search")
                    .font(.system(size: MacSessionSearchMetrics.secondarySize))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .padding(.horizontal, 8)
        .accessibilityLabel(hit.session.title)
        .accessibilityValue(hit.snippet ?? "")
        .accessibilityIdentifier("session-search-result-\(hit.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .id(hit.id)
        .onContinuousHover { phase in
            guard case .active = phase else { return }
            // Scrolling a keyboard selection under a stationary pointer must not
            // turn that newly hovered row into the next keyboard destination.
            guard keyboardPointerLocation != NSEvent.mouseLocation else { return }
            keyboardPointerLocation = nil
            selection = hit.id
        }
    }

    private func moveSelection(_ delta: Int, in hits: [SessionSearchHit]) {
        let ids = hits.map(\.id)
        guard !ids.isEmpty else { return }
        let current = selection.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : 0)
        let next = min(max(current + delta, 0), ids.count - 1)
        keyboardPointerLocation = NSEvent.mouseLocation
        selection = ids[next]
        // Hover only highlights. Keyboard navigation also reveals its destination,
        // including when it returns to the same row after a mouse selection.
        scrollRequest = SessionSearchScrollRequest(sessionID: ids[next])
    }

    private func openSelection(in hits: [SessionSearchHit]) {
        let session = hits.first { $0.id == selection }?.session ?? hits.first?.session
        guard let session else { return }
        open(session)
    }

    private func open(_ session: SessionSummary) {
        model.stopSessionSearch()
        window.revealSession(session)
    }
}

private struct SessionSearchHit: Identifiable {
    let session: SessionSummary
    let snippet: String?
    var id: SessionSummary.ID { session.id }
}

private struct SessionSearchScrollRequest: Equatable {
    let id = UUID()
    let sessionID: SessionSummary.ID
}

private enum MacSessionSearchMetrics {
    static let cornerRadius: CGFloat = 14
    static let topInset: CGFloat = 72
    static let fieldSize: CGFloat = 18
    static let titleSize: CGFloat = 16
    static let secondarySize: CGFloat = 14
}

/// Scrolls once the rows exceed `maxHeight`, and stays as short as the rows otherwise.
private struct FittingScroll<Content: View>: View {
    let maxHeight: CGFloat
    let scrollRequest: SessionSearchScrollRequest?
    let content: Content
    @State private var contentHeight: CGFloat = 0

    init(maxHeight: CGFloat, scrollRequest: SessionSearchScrollRequest?, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.scrollRequest = scrollRequest
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: SessionSearchHeightKey.self, value: proxy.size.height)
                        }
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: scrollRequest) { _, request in
                guard let request else { return }
                proxy.scrollTo(request.sessionID, anchor: .center)
            }
        }
        .onPreferenceChange(SessionSearchHeightKey.self) { contentHeight = $0 }
        .frame(height: min(max(contentHeight, 120), maxHeight))
    }
}

private struct SessionSearchHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

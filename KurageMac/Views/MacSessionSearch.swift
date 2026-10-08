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
                    .padding(.top, 18)
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
    @State private var selection: SessionSummary.ID?
    @FocusState private var queryFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hits: [SessionSearchHit] {
        let query = trimmedQuery
        return model.sessions.compactMap { session in
            guard !query.isEmpty else { return SessionSearchHit(session: session, snippet: nil) }
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
        let hits = hits
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search sessions", text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($queryFocused)
                    .accessibilityIdentifier("session-search-field")
                    .onSubmit { openSelection(in: hits) }
                    .onKeyPress(.upArrow) { moveSelection(-1, in: hits); return .handled }
                    .onKeyPress(.downArrow) { moveSelection(1, in: hits); return .handled }
                    .onKeyPress(.escape) { onClose(); return .handled }
                if model.isIndexingSessionSearch && !trimmedQuery.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Searching messages")
                }
                if !query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") {
                        query = ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("clear-session-search")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Divider()
            FittingScroll(maxHeight: 440, selection: selection) {
                resultList(hits)
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
        .task(id: trimmedQuery) {
            if trimmedQuery.isEmpty {
                model.stopSessionSearch()
            } else {
                await model.indexSessionsForSearch()
            }
        }
        .onDisappear { model.stopSessionSearch() }
    }

    private func resultList(_ hits: [SessionSearchHit]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sessions")
                .font(.subheadline)
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
                    .controlSize(.small)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.session.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                    if let snippet = hit.snippet {
                        Text(snippet)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 12)
                Text("Search")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
        .onHover { hovering in
            if hovering { selection = hit.id }
        }
    }

    private func moveSelection(_ delta: Int, in hits: [SessionSearchHit]) {
        let ids = hits.map(\.id)
        guard !ids.isEmpty else { return }
        let current = selection.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : 0)
        let next = min(max(current + delta, 0), ids.count - 1)
        selection = ids[next]
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

private enum MacSessionSearchMetrics {
    static let cornerRadius: CGFloat = 14
}

/// Scrolls once the rows exceed `maxHeight`, and stays as short as the rows otherwise.
private struct FittingScroll<Content: View>: View {
    let maxHeight: CGFloat
    let selection: SessionSummary.ID?
    let content: Content
    @State private var contentHeight: CGFloat = 0

    init(maxHeight: CGFloat, selection: SessionSummary.ID?, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.selection = selection
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
            .onChange(of: selection) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
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

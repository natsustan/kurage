import Foundation
import Observation
import KurageCore

/// Navigation and drafts belong to this window, never to the shared account service.
@MainActor
@Observable
final class MacWindowState {
    struct Draft {
        var text = ""
        var attachments: [ComposerAttachment] = []
        var runConfig = ConversationRunConfigState()
        var pendingAttachments: [MacAttachmentSource] = []
        var isLoadingAttachments: Bool { !pendingAttachments.isEmpty }
        var hasContent: Bool { !text.isEmpty || !attachments.isEmpty || isLoadingAttachments }
    }

    var selectedRootID: String?
    var search = ""
    var showsChanges = false
    var newSession: NewSessionDestination?
    private var tabs: [String: String] = [:]
    private var drafts: [String: Draft] = [:]

    subscript(draft sessionID: String) -> Draft {
        get { drafts[sessionID] ?? Draft() }
        set { drafts[sessionID] = newValue }
    }

    func openPendingStart(_ pending: PendingSessionStart, model: AppModel) throws {
        let projectName = model.sessionSummary(pending.templateSessionID)?.projectName ?? "Project"
        let id = try model.restoreSessionStart(pending, projectName: projectName)
        open(id)
    }

    @discardableResult
    func editFailedMessage(sessionID: String, model: AppModel, replacingDraft: Bool = false) -> Bool {
        guard replacingDraft || !self[draft: sessionID].hasContent else { return false }
        let start = model.pendingSessionStart(sessionID: sessionID)
        let template = start.flatMap { model.sessionSummary($0.templateSessionID) }
        // A first turn must return to the creation flow, never become an ordinary send.
        guard start == nil || template != nil else { return false }
        guard let message = model.takeFailedOutgoingMessage(sessionID: sessionID) else { return false }
        if let start, let template {
            drafts[sessionID] = nil
            open(template.id)
            newSession = NewSessionDestination(template: template, isTab: start.summary.parentSessionID != nil,
                                              restoredStart: start, restoredMessage: message)
        } else {
            self[draft: sessionID].text = message.composerText
            self[draft: sessionID].attachments = message.attachments
            self[draft: sessionID].pendingAttachments = []
            if let choice = message.runConfig,
               self[draft: sessionID].runConfig.config?.choosing(choice.value) == choice {
                self[draft: sessionID].runConfig.choose(choice.value)
            }
        }
        return true
    }

    func selectedTab(rootID: String) -> String { tabs[rootID] ?? rootID }

    func selectTab(_ id: String, rootID: String) {
        tabs[rootID] = id
    }

    func open(_ id: String, rootID: String? = nil) {
        selectedRootID = rootID ?? id
        tabs[rootID ?? id] = id
    }
}

struct NewSessionDestination: Identifiable {
    let template: SessionSummary
    let isTab: Bool
    var restoredStart: OutgoingSessionStart? = nil
    var restoredMessage: OutgoingMessage? = nil
    var id: String { "\(template.id):\(isTab)" }

    static func projectTemplates(in sessions: [SessionSummary]) -> [SessionSummary] {
        var seen = Set<String>()
        return sessions.sorted {
            ($0.lastMessageAt ?? $0.lastActivityAt ?? 0) > ($1.lastMessageAt ?? $1.lastActivityAt ?? 0)
        }.filter {
            guard $0.parentSessionID == nil, let projectID = $0.projectID,
                  projectID.hasPrefix("local:") else { return false }
            return seen.insert(projectID).inserted
        }
    }
}

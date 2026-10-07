import SwiftUI

@main
struct KurageApp: App {
    @State private var model: AppModel
    @UIApplicationDelegateAdaptor(KurageAppDelegate.self) private var appDelegate

    init() {
        let usesFixtures = ProcessInfo.processInfo.arguments.contains("--fixture")
        let client: any LodyClient = ProcessInfo.processInfo.arguments.contains("--fixture")
            ? FixtureLodyClient(records: ProcessInfo.processInfo.arguments.contains("--fixture-agent-error")
                ? [SessionRecord.errorSample] + SessionRecord.samples
                : ProcessInfo.processInfo.arguments.contains("--fixture-subtask-statuses")
                ? SessionRecord.samplesWithSubtaskStatuses
                : ProcessInfo.processInfo.arguments.contains("--fixture-subtasks")
                    ? SessionRecord.samplesWithSubtasks
                    : ProcessInfo.processInfo.arguments.contains("--fixture-questions")
                        ? [SessionRecord.questionSample] + SessionRecord.samples
                        : ProcessInfo.processInfo.arguments.contains("--fixture-running-tab")
                            ? SessionRecord.samplesWithRunningTab
                            : ProcessInfo.processInfo.arguments.contains("--fixture-long-session-list")
                                ? SessionRecord.samplesWithLongSessionList
                                : ProcessInfo.processInfo.arguments.contains("--fixture-unassigned-session")
                                    ? SessionRecord.samplesWithUnassignedSession : SessionRecord.samples,
                failingConversationIDsOnce:
                ProcessInfo.processInfo.arguments.contains("--fixture-search-failure") ? ["session-long"] : [],
                conversationDelay: ProcessInfo.processInfo.arguments.contains("--fixture-slow-conversation") ? .seconds(3) : nil,
                failStartAndArchiveProjectOnce: ProcessInfo.processInfo.arguments.contains("--fixture-start-unconfirmed"),
                rejectStartOnce: ProcessInfo.processInfo.arguments.contains("--fixture-start-rejected"),
                sendDelay: ProcessInfo.processInfo.arguments.contains("--fixture-tab-send") ? .seconds(15)
                    : ProcessInfo.processInfo.arguments.contains("--fixture-slow-send") ? .seconds(3) : nil,
                startDelay: ProcessInfo.processInfo.arguments.contains("--fixture-slow-start") ? .seconds(8) : nil,
                failSendOnce: ProcessInfo.processInfo.arguments.contains("--fixture-send-unconfirmed"),
                rejectSendOnce: ProcessInfo.processInfo.arguments.contains("--fixture-send-rejected"),
                rejectMissingHistoryOnce: ProcessInfo.processInfo.arguments.contains("--fixture-send-not-delivered"),
                failTabStartOnce: ProcessInfo.processInfo.arguments.contains("--fixture-tab-start-unconfirmed"),
                skillRefreshDelay: ProcessInfo.processInfo.arguments.contains("--fixture-skill-refresh") ? .seconds(3) : nil,
                mentionDelay: ProcessInfo.processInfo.arguments.contains("--fixture-slow-mentions") ? .seconds(6) : nil,
                failSkillRefreshOnce: ProcessInfo.processInfo.arguments.contains("--fixture-skill-refresh"),
                authorizationDelay: ProcessInfo.processInfo.arguments.contains("--fixture-browser")
                    ? ProcessInfo.processInfo.arguments.contains("--fixture-pending-authorization") ? .seconds(600) : .seconds(12)
                    : nil,
                streamsConversationUpdates: true,
                failFilePreviewOnce: ProcessInfo.processInfo.arguments.contains("--fixture-file-preview-failure"),
                filePreviewUnavailableReason: ProcessInfo.processInfo.arguments.contains("--fixture-file-preview-too-large")
                    ? "too_large" : nil,
                filePreviewDelay: ProcessInfo.processInfo.arguments.contains("--fixture-slow-file-preview")
                    ? .seconds(3) : .milliseconds(200),
                filePreviewLargeRewrite: ProcessInfo.processInfo.arguments.contains("--fixture-file-preview-large-rewrite"),
                projectGitFailureOnce: ProcessInfo.processInfo.arguments.contains("--fixture-project-git-failure") ? .accessDenied : nil,
                projectGitStates: FixtureLodyClient.quickActionGitStates(arguments: ProcessInfo.processInfo.arguments),
                workspaceSummaries: ProcessInfo.processInfo.arguments.contains("--fixture-empty-workspaces") ? []
                    : ProcessInfo.processInfo.arguments.contains("--fixture-many-workspaces")
                        ? [WorkspaceSummary(id: "ws-demo", name: "Demo", slug: "demo")] + (1...12).map {
                            WorkspaceSummary(id: "ws-extra-\($0)", name: "Studio \($0) · Mobile Application Development",
                                             slug: "mobile-studio-\($0)")
                        }
                    : ProcessInfo.processInfo.arguments.contains("--fixture-settings")
                        ? [WorkspaceSummary(id: "ws-demo", name: "Demo", slug: "demo"),
                           WorkspaceSummary(id: "ws-studio", name: "Studio", slug: "studio")]
                        : [WorkspaceSummary(id: "ws-demo", name: "Demo", slug: "demo")],
                workspaceRefreshDelay: ProcessInfo.processInfo.arguments.contains("--fixture-slow-workspaces") ? .seconds(15)
                    : ProcessInfo.processInfo.arguments.contains("--fixture-workspace-failure") ? .seconds(1) : nil,
                failWorkspaceRefreshOnce: ProcessInfo.processInfo.arguments.contains("--fixture-workspace-failure"),
                hasModelHistory: !ProcessInfo.processInfo.arguments.contains("--fixture-no-model-history"),
                accountID: ProcessInfo.processInfo.arguments.contains("--fixture-notifications") ? "fixture-user" : nil)
            : HTTPLodyClient()
        let notificationService: any PushNotificationService = usesFixtures
            ? FixturePushNotificationService(isConfigured: ProcessInfo.processInfo.arguments.contains("--fixture-notifications"))
            : OneSignalNotificationService.shared
        let notifications = NotificationModel(service: notificationService, defaults: usesFixtures ? nil : .standard)
        if usesFixtures, ProcessInfo.processInfo.arguments.contains("--fixture-notification-click") {
            let sessionID = ProcessInfo.processInfo.arguments.contains("--fixture-running-tab") ? "fixture-running-tab" : "session-long"
            if let route = NotificationRoute("/demo/sessions/\(sessionID)") {
                let recipient = ProcessInfo.processInfo.arguments.contains("--fixture-notification-wrong-account") ? "other-user" : "fixture-user"
                notifications.receive(NotificationClick(id: "fixture-push", route: route, userID: recipient))
            }
        }
        _model = State(initialValue: AppModel(client: client, notifications: notifications))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

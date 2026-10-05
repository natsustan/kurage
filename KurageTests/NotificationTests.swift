import Foundation
import Testing
@testable import Kurage

struct NotificationIdentityTests {
    @Test func legacyColdClickSurvivesMatchingAccountRestoration() throws {
        var identity = NotificationIdentity(legacyRecipientID: "user-a")
        let owner = try #require(identity.recipientUserID(nil))
        let capturedGeneration = identity.generation
        #expect(owner == "user-a")
        #expect(identity.acceptsClick(userID: owner, capturedGeneration: capturedGeneration))

        identity.identify("user-a")
        #expect(identity.recipientUserID(nil) == owner)
        #expect(identity.acceptsClick(userID: owner, capturedGeneration: capturedGeneration))
        identity.identify("user-a")
        #expect(identity.recipientUserID(nil) == owner)
    }

    @Test(arguments: [false, true])
    func accountSwitchRejectsOwnerlessPayloadsAndPreservesExplicitRecipients(signOutFirst: Bool) {
        var identity = NotificationIdentity(legacyRecipientID: "user-a")
        identity.identify("user-a")
        if signOutFirst { identity.identify(nil) }
        identity.identify("user-b")

        #expect(identity.recipientUserID(nil) == nil)
        #expect(identity.recipientUserID("user-b") == "user-b")
        #expect(identity.acceptsClick(userID: "user-b", capturedGeneration: identity.generation))
        #expect(!identity.acceptsClick(userID: "user-a", capturedGeneration: identity.generation))

        identity.identify("user-a")
        #expect(identity.recipientUserID(nil) == nil)
        #expect(identity.acceptsClick(userID: "user-a", capturedGeneration: identity.generation))
    }

    @Test func signOutAndSameAccountReLoginDoNotRestoreLegacyFallback() {
        var identity = NotificationIdentity(legacyRecipientID: "user-a")
        identity.identify("user-a")
        identity.identify(nil)
        #expect(identity.recipientUserID(nil) == nil)
        #expect(!identity.acceptsClick(userID: "user-a", capturedGeneration: identity.generation))

        identity.identify("user-a")
        #expect(identity.recipientUserID(nil) == nil)
        #expect(identity.recipientUserID("user-a") == "user-a")
        #expect(identity.acceptsClick(userID: "user-a", capturedGeneration: identity.generation))
    }

    @Test func restoringAnotherAccountRejectsLegacyColdClick() throws {
        var identity = NotificationIdentity(legacyRecipientID: "user-a")
        let owner = try #require(identity.recipientUserID(nil))
        let capturedGeneration = identity.generation
        identity.identify("user-b")

        #expect(identity.recipientUserID(nil) == nil)
        #expect(!identity.acceptsClick(userID: owner, capturedGeneration: capturedGeneration))
        #expect(identity.acceptsClick(userID: "user-b", capturedGeneration: identity.generation))
    }

    @Test func unknownStartupIdentityCannotAttributeOwnerlessPayloadsToFirstAccount() {
        var identity = NotificationIdentity()
        #expect(identity.recipientUserID(nil) == nil)
        let capturedGeneration = identity.generation
        identity.identify("user-a")

        #expect(identity.recipientUserID(nil) == nil)
        #expect(identity.recipientUserID("user-a") == "user-a")
        #expect(identity.acceptsClick(userID: "user-a", capturedGeneration: capturedGeneration))
    }

    @Test func queuedClickIsRejectedAfterSwitchingAwayAndBack() {
        var identity = NotificationIdentity(legacyRecipientID: "user-a")
        identity.identify("user-a")
        let capturedGeneration = identity.generation
        identity.identify("user-b")
        identity.identify("user-a")

        #expect(!identity.acceptsClick(userID: "user-a", capturedGeneration: capturedGeneration))
        #expect(identity.recipientUserID(nil) == nil)
    }

    @Test func emptyRecipientDoesNotUseLegacyFallback() {
        let identity = NotificationIdentity(legacyRecipientID: "user-a")
        #expect(identity.recipientUserID("") == nil)
        #expect(NotificationIdentity(legacyRecipientID: "").recipientUserID(nil) == nil)
    }
}

@MainActor
struct NotificationTests {
    @Test func routeDecodesComponents() throws {
        let route = try #require(NotificationRoute("/my%20workspace/sessions/session-123"))
        #expect(route.workspace == "my workspace")
        #expect(route.sessionID == "session-123")
    }

    @Test(arguments: ["", "https://lody.ai/demo/sessions/s", "//demo/sessions/s", "/demo/sessions/",
                      "/demo/sessions/s/extra", "/demo/sessions/s?key=1", "/demo/sessions/s#fragment",
                      "/%2E%2E/sessions/s", "/demo/sessions/%2Fsecret", "/demo/sessions/%5Csecret",
                      "/demo/sessions/%00", "/demo/sessions/%ZZ", "/demo/sessions/%3Fquery"])
    func malformedRoutesAreRejected(path: String) { #expect(NotificationRoute(path) == nil) }

    @Test func coldClickWaitsForMatchingAccountAndIsDeduplicated() throws {
        let model = NotificationModel(service: FixturePushNotificationService())
        let click = try makeClick()
        model.receive(click)
        #expect(model.pendingClick == click)
        model.identify("user")
        #expect(model.pendingClick == click)
        model.acknowledge(click.id)
        model.receive(click)
        #expect(model.pendingClick == nil)
        model.receive(try makeClick(id: "other", user: "another-user"))
        #expect(model.pendingClick == nil)
    }

    @Test func accountChangeAndSignOutDiscardBufferedAndLateClicks() throws {
        let service = NotificationServiceSpy()
        let model = NotificationModel(service: service)
        model.receive(try makeClick())
        model.identify("another-user")
        #expect(model.pendingClick == nil)
        #expect(service.userID == "another-user")
        model.signOut()
        model.receive(try makeClick(id: "late"))
        #expect(model.pendingClick == nil)
        #expect(service.userID == nil)
        #expect(service.clearCount == 1)
        #expect(!service.currentStatus.isSubscribed)
    }

    @Test func permissionIsRequestedOnlyByExplicitEnable() async {
        let service = FixturePushNotificationService(isConfigured: true)
        let model = NotificationModel(service: service)
        model.identify("user")
        await model.refresh()
        #expect(service.requestCount == 0)
        #expect(!model.isEnabled)
        await model.setEnabled(true)
        #expect(service.requestCount == 1)
        #expect(model.isEnabled)
        #expect(service.currentStatus.isRegistered)
        await model.setEnabled(false)
        #expect(service.requestCount == 1)
        #expect(!model.isEnabled)
        #expect(!service.currentStatus.isSubscribed)
    }

    @Test func deniedPermissionDoesNotEnableSubscription() async {
        let service = FixturePushNotificationService(isConfigured: true)
        service.grantsAuthorization = false
        let model = NotificationModel(service: service)
        model.identify("user")
        await model.setEnabled(true)
        #expect(model.status.authorization == .denied)
        #expect(!model.isEnabled)
        #expect(!service.currentStatus.isSubscribed)
    }

    @Test func latePermissionResultCannotSubscribeSignedOutUser() async throws {
        let service = NotificationServiceSpy()
        service.deferAuthorization = true
        let model = NotificationModel(service: service)
        model.identify("user")
        var requests = service.authorizationRequests.makeAsyncIterator()
        let enable = Task { await model.setEnabled(true) }
        let requested = await requests.next()
        try #require(requested != nil)
        model.signOut()
        service.completeAuthorization()
        await enable.value
        #expect(!model.isEnabled)
        #expect(!model.isUpdating)
        #expect(!service.currentStatus.isSubscribed)
    }

    @Test func oldConversationCannotClearNewForegroundVisibility() {
        let service = NotificationServiceSpy()
        let model = NotificationModel(service: service)
        let old = UUID(), current = UUID()
        let workspace = WorkspaceSummary(id: "ws", name: "Demo", slug: "demo")
        model.setVisibleSession(owner: old, workspace: workspace, sessionID: "old")
        model.setVisibleSession(owner: current, workspace: workspace, sessionID: "current")
        model.setVisibleSession(owner: old, workspace: nil, sessionID: nil)
        #expect(service.visibleSessionID == "current")
        model.setVisibleSession(owner: current, workspace: nil, sessionID: nil)
        #expect(service.visibleSessionID == nil)
    }

    @Test func preferenceRestoresWithoutPromptAndDoesNotWaitForRegistration() async throws {
        let suite = "kurage-notifications-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let firstService = FixturePushNotificationService(isConfigured: true)
        let first = NotificationModel(service: firstService, defaults: defaults)
        first.identify("user")
        await first.setEnabled(true)
        first.signOut()

        let restoredService = FixturePushNotificationService(isConfigured: true)
        restoredService.currentStatus.authorization = .authorized
        let restored = NotificationModel(service: restoredService, defaults: defaults)
        restored.identify("user")
        await restored.refresh()
        #expect(restored.isEnabled)
        #expect(restoredService.requestCount == 0)
        restoredService.currentStatus.isSubscribed = false
        restoredService.currentStatus.isRegistered = false
        await restored.refresh()
        #expect(restored.isEnabled)
        await restored.setEnabled(false)

        let disabledService = FixturePushNotificationService(isConfigured: true)
        disabledService.currentStatus.authorization = .authorized
        let disabled = NotificationModel(service: disabledService, defaults: defaults)
        disabled.identify("user")
        await disabled.refresh()
        #expect(!disabled.isEnabled)
        #expect(!disabledService.currentStatus.isSubscribed)
        #expect(disabledService.requestCount == 0)
    }

    private func makeClick(id: String = "push", user: String = "user") throws -> NotificationClick {
        NotificationClick(id: id, route: try #require(NotificationRoute("/demo/sessions/root")), userID: user)
    }
}

@MainActor
private final class NotificationServiceSpy: PushNotificationService {
    let isConfigured = true
    var onClick: (@MainActor (NotificationClick) -> Void)?
    var onStatusChange: (@MainActor () -> Void)?
    var userID: String?
    var currentStatus = PushNotificationStatus()
    var visibleSessionID: String?
    var clearCount = 0
    var deferAuthorization = false
    let authorizationRequests: AsyncStream<Bool>
    private let requestSignal: AsyncStream<Bool>.Continuation
    private var authorization: CheckedContinuation<Bool, Never>?

    init() { (authorizationRequests, requestSignal) = AsyncStream.makeStream() }
    func identify(_ userID: String?, enabled: Bool) { self.userID = userID; setSubscribed(enabled && userID != nil) }
    func setSubscribed(_ enabled: Bool) { currentStatus.isSubscribed = enabled }
    func status() async -> PushNotificationStatus { currentStatus }
    func requestAuthorization() async -> Bool {
        if !deferAuthorization { return true }
        return await withCheckedContinuation { authorization = $0; requestSignal.yield(true) }
    }
    func completeAuthorization() { authorization?.resume(returning: true); authorization = nil }
    func setVisibleSession(workspace: WorkspaceSummary?, sessionID: String?) { visibleSessionID = sessionID }
    func clearDelivered() { clearCount += 1 }
}

@MainActor
struct NotificationNavigationTests {
    @Test(arguments: ["demo", "ws-demo"])
    func rootClickResolvesWithinWorkspace(workspace: String) async throws {
        let client = NotificationRoutingClient()
        let model = await prepare(client)
        model.notifications.receive(try click(workspace: workspace))
        await model.openPendingNotification()
        #expect(model.notificationNavigation?.rootSessionID == "root")
        #expect(model.notificationNavigation?.workspaceID == "ws-demo")
        #expect(client.destinationWorkspaces == ["ws-demo"])
        #expect(model.notifications.pendingClick == nil)
    }

    @Test func closedTabReopensAndSelectsItsRoot() async throws {
        let client = NotificationRoutingClient()
        client.destination = NotificationSessionDestination(rootSessionID: "root", sessionID: "tab", isTabClosed: true)
        let model = await prepare(client)
        model.notifications.receive(try click(session: "tab"))
        await model.openPendingNotification()
        #expect(model.notificationNavigation?.sessionID == "tab")
        #expect(model.activeSessionTab(rootID: "root") == "tab")
        #expect(client.reopenedTabs == ["ws-demo:tab"])
    }

    @Test func clickSwitchesToAuthorizedWorkspace() async throws {
        let client = NotificationRoutingClient()
        let model = await prepare(client)
        model.notifications.receive(try click(workspace: "studio"))
        await model.openPendingNotification()
        #expect(model.selectedWorkspaceID == "ws-studio")
        #expect(model.notificationNavigation?.workspaceID == "ws-studio")
        #expect(client.destinationWorkspaces == ["ws-studio"])
    }

    @Test func inaccessibleWorkspaceNeverResolvesSession() async throws {
        let client = NotificationRoutingClient()
        let model = await prepare(client)
        model.notifications.receive(try click(workspace: "removed"))
        await model.openPendingNotification()
        #expect(model.notificationNavigation == nil)
        #expect(client.destinationWorkspaces.isEmpty)
        #expect(model.notifications.routingError != nil)
        #expect(model.notifications.pendingClick == nil)
    }

    @Test func missingSessionDoesNotNavigate() async throws {
        let client = NotificationRoutingClient()
        client.destination = nil
        let model = await prepare(client)
        model.notifications.receive(try click())
        await model.openPendingNotification()
        #expect(model.notificationNavigation == nil)
        #expect(model.notifications.routingError != nil)
        #expect(model.notifications.pendingClick == nil)
    }

    @Test func failureRetainsClickForRetry() async throws {
        let client = NotificationRoutingClient()
        client.failsDestination = true
        let model = await prepare(client)
        let incoming = try click()
        model.notifications.receive(incoming)
        await model.openPendingNotification()
        #expect(model.notifications.pendingClick == incoming)
        #expect(model.notifications.routingError != nil)
        client.failsDestination = false
        await model.openPendingNotification()
        #expect(model.notificationNavigation?.clickID == incoming.id)
        #expect(model.notifications.pendingClick == nil)
    }

    @Test(arguments: ["signOut", "switchWorkspace", "background", "cancel"])
    func lateResolutionCannotNavigateAfterContextChanges(change: String) async throws {
        let client = NotificationRoutingClient()
        client.defersDestination = true
        let model = await prepare(client)
        var requests = client.destinationRequests.makeAsyncIterator()
        model.notifications.receive(try click())
        let routing = Task { await model.openPendingNotification() }
        let requested = await requests.next()
        try #require(requested != nil)
        switch change {
        case "signOut": model.signOut()
        case "switchWorkspace": await model.selectWorkspace("ws-studio"); await model.selectWorkspace("ws-demo")
        case "background": model.setApplicationActive(false)
        default: routing.cancel()
        }
        client.completeDestination()
        await routing.value
        #expect(model.notificationNavigation == nil)
        #expect(client.reopenedTabs.isEmpty)
    }

    @Test func manualWorkspaceSwitchDuringDiscoveryDiscardsTheClick() async throws {
        let client = NotificationRoutingClient()
        let model = await prepare(client)
        client.defersWorkspaces = true
        var requests = client.workspaceRequests.makeAsyncIterator()
        model.notifications.receive(try click())
        let routing = Task { await model.openPendingNotification() }
        let request = try #require(await requests.next())
        await model.selectWorkspace("ws-studio")
        client.completeWorkspaces(request)
        await routing.value
        #expect(model.selectedWorkspaceID == "ws-studio")
        #expect(model.notificationNavigation == nil)
        #expect(model.notifications.pendingClick == nil)
        #expect(client.destinationWorkspaces.isEmpty)
    }

    @Test(arguments: [false, true], [false, true])
    func supersededWorkspaceRefreshRetainsNotificationForRetry(hasCachedWorkspaces: Bool, latestFails: Bool) async throws {
        let client = NotificationRoutingClient()
        let cached = hasCachedWorkspaces ? [client.workspaceCatalog[0]] : []
        client.workspaceCatalog = cached
        let model = await prepare(client)
        let refreshed = [WorkspaceSummary(id: "ws-studio", name: "Studio", slug: "studio")]
        client.defersWorkspaces = true
        var requests = client.workspaceRequests.makeAsyncIterator()
        let incoming = try click(workspace: "studio")
        model.notifications.receive(incoming)
        let routing = Task { await model.openPendingNotification() }
        let routingRequest = try #require(await requests.next())
        let latestRefresh = Task { await model.refreshWorkspaces() }
        let latestRequest = try #require(await requests.next())

        client.completeWorkspaces(routingRequest, with: refreshed)
        await routing.value
        #expect(model.workspaces == cached)
        #expect(model.isRefreshingWorkspaces)
        #expect(model.notificationNavigation == nil)
        #expect(client.destinationWorkspaces.isEmpty)
        #expect(model.notifications.pendingClick == incoming)
        #expect(model.notifications.routingError == "Could not load this conversation. Try again when connected.")

        if latestFails { client.failWorkspaces(latestRequest) }
        else { client.completeWorkspaces(latestRequest, with: refreshed) }
        #expect(await latestRefresh.value == !latestFails)
        #expect(model.notifications.pendingClick == incoming)
        #expect((model.workspaceLoadStatusNote != nil) == latestFails)

        client.workspaceCatalog = refreshed
        client.defersWorkspaces = false
        await model.openPendingNotification()
        #expect(model.notificationNavigation?.clickID == incoming.id)
        #expect(model.notificationNavigation?.workspaceID == "ws-studio")
        #expect(client.destinationWorkspaces == ["ws-studio"])
        #expect(model.notifications.pendingClick == nil)
        #expect(model.notifications.routingError == nil)
    }

    @Test func failedSessionRefreshKeepsANewWorkspaceClickForRetry() async throws {
        let client = NotificationRoutingClient()
        let model = await prepare(client)
        client.failingSessionWorkspaceID = "ws-studio"
        let incoming = try click(workspace: "studio")
        model.notifications.receive(incoming)
        await model.openPendingNotification()
        #expect(model.selectedWorkspaceID == "ws-studio")
        #expect(model.notifications.pendingClick == incoming)
        #expect(model.notifications.routingError != nil)
        #expect(client.destinationWorkspaces.isEmpty)
        client.failingSessionWorkspaceID = nil
        await model.openPendingNotification()
        #expect(model.notificationNavigation?.clickID == incoming.id)
        #expect(model.notifications.pendingClick == nil)
    }

    @Test func cancelledRoutingStopsItsOwnedSessionRefresh() async throws {
        let client = NotificationRoutingClient()
        let model = await prepare(client)
        client.delaysSessions = true
        var requests = client.sessionRequests.makeAsyncIterator()
        model.notifications.receive(try click())
        let routing = Task { await model.openPendingNotification() }
        try #require(await requests.next() != nil)
        routing.cancel()
        await routing.value
        #expect(client.sessionRequestCancelled)
        #expect(model.notificationNavigation == nil)
        #expect(client.destinationWorkspaces.isEmpty)
    }

    private func prepare(_ client: NotificationRoutingClient) async -> AppModel {
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        return model
    }

    private func click(workspace: String = "demo", session: String = "root") throws -> NotificationClick {
        NotificationClick(id: UUID().uuidString, route: try #require(NotificationRoute("/\(workspace)/sessions/\(session)")), userID: "user")
    }
}

@MainActor
private final class NotificationRoutingClient: LodyClient {
    private(set) var account: Account? = Account(email: "fixture@kurage.app", id: "user")
    var supportsSessionMetadataEditing: Bool { true }
    var destination: NotificationSessionDestination? = NotificationSessionDestination(rootSessionID: "root", sessionID: "root", isTabClosed: false)
    var failsDestination = false
    var defersDestination = false
    var defersWorkspaces = false
    var workspaceCatalog = [WorkspaceSummary(id: "ws-demo", name: "Demo", slug: "demo"),
                            WorkspaceSummary(id: "ws-studio", name: "Studio", slug: "studio")]
    var failingSessionWorkspaceID: String?
    var delaysSessions = false
    private(set) var sessionRequestCancelled = false
    private(set) var destinationWorkspaces: [String] = []
    private(set) var reopenedTabs: [String] = []
    let destinationRequests: AsyncStream<Bool>
    private let requestSignal: AsyncStream<Bool>.Continuation
    private var pending: CheckedContinuation<NotificationSessionDestination?, Never>?
    let workspaceRequests: AsyncStream<UUID>
    private let workspaceSignal: AsyncStream<UUID>.Continuation
    private var pendingWorkspaces: [UUID: CheckedContinuation<[WorkspaceSummary], Error>] = [:]
    let sessionRequests: AsyncStream<Bool>
    private let sessionSignal: AsyncStream<Bool>.Continuation
    init() {
        (destinationRequests, requestSignal) = AsyncStream.makeStream()
        (workspaceRequests, workspaceSignal) = AsyncStream.makeStream()
        (sessionRequests, sessionSignal) = AsyncStream.makeStream()
    }
    func restoreSession() async -> Account? { account }
    func signOut() { account = nil }
    func workspaces() async throws -> [WorkspaceSummary] {
        if defersWorkspaces {
            return try await withCheckedThrowingContinuation { continuation in
                let id = UUID()
                pendingWorkspaces[id] = continuation
                workspaceSignal.yield(id)
            }
        }
        return workspaceCatalog
    }
    func completeWorkspaces(_ id: UUID, with catalog: [WorkspaceSummary]? = nil) {
        pendingWorkspaces.removeValue(forKey: id)?.resume(returning: catalog ?? workspaceCatalog)
    }
    func failWorkspaces(_ id: UUID) {
        pendingWorkspaces.removeValue(forKey: id)?.resume(throwing: LodyClientError.unreachable)
    }
    func sessions(workspaceID: String) async throws -> [SessionSummary] {
        if workspaceID == failingSessionWorkspaceID { throw LodyClientError.unreachable }
        if delaysSessions {
            sessionSignal.yield(true)
            do { try await Task.sleep(for: .seconds(60)) }
            catch { sessionRequestCancelled = true; throw error }
        }
        return [SessionSummary(id: "root", title: "Root", agentName: "Agent", activity: .idle, preview: "")]
    }
    func notificationDestination(sessionID: String, workspaceID: String) async throws -> NotificationSessionDestination? {
        destinationWorkspaces.append(workspaceID)
        if failsDestination { throw LodyClientError.unreachable }
        if defersDestination { return await withCheckedContinuation { pending = $0; requestSignal.yield(true) } }
        return destination
    }
    func completeDestination() { pending?.resume(returning: destination); pending = nil }
    func updateSessionMetadata(_ change: SessionMetadataChange, sessionID: String, workspaceID: String) async throws {
        if case .tabClosed(false) = change { reopenedTabs.append("\(workspaceID):\(sessionID)") }
    }
    func beginDeviceAuthorization() async throws -> DeviceAuthorization { throw LodyClientError.notConnected }
    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws { throw LodyClientError.notConnected }
    func conversation(sessionID: String, workspaceID: String) async throws -> Conversation { throw LodyClientError.notConnected }
    func send(_ text: String, attachments: [ComposerAttachment], runConfig: RunConfigChoice?, turnID: String,
              sessionID: String, workspaceID: String) async throws -> RunConfigChoice? { throw LodyClientError.notConnected }
    func cancelSession(sessionID: String, workspaceID: String) async throws { throw LodyClientError.notConnected }
    func respond(_ decision: PermissionDecision, requestID: String, sessionID: String, workspaceID: String) async throws { throw LodyClientError.notConnected }
}

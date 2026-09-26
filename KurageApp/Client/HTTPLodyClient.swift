import Foundation
import CryptoKit

/// Device authorization and workspace sessions from Lody.
@MainActor
final class HTTPLodyClient: LodyClient {
    let supportsConversations = true
    var supportsTextSending: Bool { account?.id?.isEmpty == false }
    var supportsSessionCreation: Bool { supportsTextSending }
    let supportsSessionCancellation = true
    let supportsSessionArchiving = true

    private struct SendKey: Hashable {
        let userID: String
        let workspaceID: String
        let sessionID: String
    }

    private struct SessionImageCacheKey: Hashable {
        let credentialID: String
        let workspaceID: String
        let sessionID: String
        let imageID: String
        let variant: SessionImageVariant
    }

    private struct PendingSend {
        let text: String
        let turnID: String
        let runConfig: RunConfigChoice?
    }

    private struct StartKey: Hashable {
        let userID: String
        let workspaceID: String
        let projectID: String
    }

    private struct PendingStart {
        let text: String
        let sessionID: String
        let turnID: String
        let agentConfigID: String?
        let selections: [RunConfigChoice]
    }

    private struct SessionImageLoad {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Data, Error>]
    }

    private let session: URLSession
    private let tokenStore: any AuthTokenStore
    private let baseURL: URL
    private let imageBaseURL: URL
    // A shared queue also orders writes from successive client instances.
    private static let cacheQueue = DispatchQueue(label: "ai.lody.kurage.session-cache", qos: .utility)
    private var lastScheduledCache: SavedSession?
    private let cacheURL: URL
    private(set) var cachedSession: SessionCache?
    private(set) var account: Account?
    private var authenticationGeneration = 0
    private var sessionBridge: SessionSyncBridge?
    private var streamsAccessCache: [WorkspaceSummary.ID: (access: StreamsAccess, expiresAt: Date, accountToken: String)] = [:]
    private var pendingSends: [SendKey: PendingSend] = [:]
    private var pendingStarts: [StartKey: PendingStart] = [:]
    private var activeStarts: [StartKey: UUID] = [:]
    private var sessionImageCache: [SessionImageCacheKey: Data] = [:]
    private var sessionImageOrder: [SessionImageCacheKey] = []
    private var sessionImageLoads: [SessionImageCacheKey: SessionImageLoad] = [:]

    init(
        session: URLSession = .shared,
        tokenStore: any AuthTokenStore = KeychainAuthTokenStore(),
        baseURL: URL = LodyEndpoints.authBaseURL,
        imageBaseURL: URL = LodyEndpoints.cloudAPIBaseURL,
        cacheURL: URL? = nil
    ) {
        self.session = session
        self.tokenStore = tokenStore
        self.baseURL = baseURL
        self.imageBaseURL = imageBaseURL
        self.cacheURL = cacheURL ?? URL.applicationSupportDirectory
            .appendingPathComponent("Kurage", isDirectory: true)
            .appendingPathComponent("session-cache.json")
        if let token = tokenStore.read(), !token.isEmpty,
           let data = try? Data(contentsOf: self.cacheURL),
           let saved = try? JSONDecoder().decode(SavedSession.self, from: data),
           saved.credentialID == Self.credentialID(token, baseURL: baseURL) {
            cachedSession = saved.cache
            account = saved.cache.account
            lastScheduledCache = saved
        }

    }

    func beginDeviceAuthorization() async throws -> DeviceAuthorization {
        authenticationGeneration += 1
        let (_, data) = try await perform(
            path: "api/auth/device/code",
            method: "POST",
            json: DeviceCodeRequest(clientID: LodyEndpoints.deviceClientID),
            token: nil,
            acceptAnyStatus: false
        )
        let body = try JSONDecoder().decode(DeviceCodeBody.self, from: data)
        guard body.expiresIn > 0, body.interval > 0 else { throw LodyClientError.signInFailed }
        return DeviceAuthorization(
            userCode: body.userCode,
            verificationURL: try Self.authorizationPage(body.verificationURIComplete),
            deviceCode: body.deviceCode,
            expiresIn: body.expiresIn,
            interval: body.interval
        )
    }

    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws {
        authenticationGeneration += 1
        var interval = authorization.interval
        var lastPollFailedToConnect = false
        let deadline = Date().addingTimeInterval(authorization.expiresIn)
        while Date() < deadline {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            try await Task.sleep(for: .seconds(min(interval, remaining)))
            try Task.checkCancellation()
            if Date() >= deadline { break }

            let status: Int
            let data: Data
            do {
                (status, data) = try await perform(
                    path: "api/auth/device/token",
                    method: "POST",
                    json: DeviceTokenRequest(
                        clientID: LodyEndpoints.deviceClientID,
                        deviceCode: authorization.deviceCode
                    ),
                    token: nil,
                    acceptAnyStatus: true
                )
            } catch LodyClientError.unreachable {
                lastPollFailedToConnect = true
                continue
            }
            if status >= 500 {
                lastPollFailedToConnect = true
                continue
            }
            lastPollFailedToConnect = false
            let body = try JSONDecoder().decode(DeviceTokenBody.self, from: data)
            if let token = body.accessToken, !token.isEmpty {
                let loadedAccount = try await loadAccount(token: token)
                try Task.checkCancellation()
                guard tokenStore.write(token) else { throw LodyClientError.signInFailed }
                account = loadedAccount
                saveSessionCache(SessionCache(account: loadedAccount))
                return
            }
            switch body.error {
            case "authorization_pending":
                continue
            case "slow_down":
                interval += 5
                continue
            case "access_denied":
                throw LodyClientError.accessDenied
            case "expired_token":
                throw LodyClientError.codeExpired
            default:
                throw LodyClientError.signInFailed
            }
        }
        throw lastPollFailedToConnect ? LodyClientError.unreachable : LodyClientError.codeExpired
    }

    func restoreSession() async -> Account? {
        let generation = authenticationGeneration
        guard let token = tokenStore.read(), !token.isEmpty else {
            signOut()
            return nil
        }
        do {
            let data = try await send(path: "api/auth/get-session", method: "GET", json: Optional<String>.none, token: token)
            guard generation == authenticationGeneration, tokenStore.read() == token else { return nil }
            if data == Data("null".utf8) {
                signOut()
                return nil
            }
            let parsed = try JSONDecoder().decode(SessionResponse.self, from: data)
            guard let email = parsed.user?.email, !email.isEmpty else {
                signOut()
                return nil
            }
            let restored = Account(email: email, id: parsed.user?.id)
            account = restored
            var cache = cachedSession ?? SessionCache(account: restored)
            cache.account = restored
            saveSessionCache(cache)
            return restored
        } catch LodyClientError.signedOut {
            guard generation == authenticationGeneration, tokenStore.read() == token else { return nil }
            signOut()
            return nil
        } catch {
            return generation == authenticationGeneration ? account : nil
        }
    }

    func signOut() {
        authenticationGeneration += 1
        tokenStore.delete()
        account = nil
        sessionBridge?.close()
        sessionBridge = nil
        streamsAccessCache = [:]
        pendingSends = [:]
        pendingStarts = [:]
        activeStarts = [:]
        for load in sessionImageLoads.values {
            load.task.cancel()
            for waiter in load.waiters.values { waiter.resume(throwing: LodyClientError.signedOut) }
        }
        sessionImageLoads = [:]
        sessionImageCache = [:]
        sessionImageOrder = []
        cachedSession = nil
        lastScheduledCache = nil
        let cacheURL = cacheURL
        Self.cacheQueue.async {
            try? FileManager.default.removeItem(at: cacheURL)
        }
    }

    func saveSessionCache(_ cache: SessionCache) {
        guard cache.account == account, let token = tokenStore.read(), !token.isEmpty else { return }
        cachedSession = cache
        let saved = SavedSession(credentialID: Self.credentialID(token, baseURL: baseURL), cache: cache)
        guard saved != lastScheduledCache else { return }
        lastScheduledCache = saved
        let cacheURL = cacheURL
        Self.cacheQueue.async { [weak self] in
            do {
                let data = try JSONEncoder().encode(saved)
                try FileManager.default.createDirectory(
                    at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try data.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                var url = cacheURL
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try url.setResourceValues(values)
            } catch {
                // Keep the in-memory session usable and allow this snapshot to be retried.
                Task { @MainActor [weak self] in
                    if self?.lastScheduledCache == saved {
                        self?.lastScheduledCache = nil
                    }
                }
            }
        }
    }

    /// Waits for already scheduled persistence operations without blocking the main actor.
    func flushSessionCache() async {
        await withCheckedContinuation { continuation in
            Self.cacheQueue.async { continuation.resume() }
        }
    }

    private struct SavedSession: Codable, Equatable, Sendable {
        var credentialID: String
        var cache: SessionCache
    }

    private static func credentialID(_ token: String, baseURL: URL) -> String {
        SHA256.hash(data: Data((baseURL.absoluteString + "\n" + token).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    func workspaces() async throws -> [WorkspaceSummary] {
        guard account != nil, let token = tokenStore.read() else { throw LodyClientError.signedOut }
        let data = try await send(
            path: "api/auth/organization/list",
            method: "GET",
            json: Optional<String>.none,
            token: token
        )
        let organizations = try decodeOrganizations(data)
        return organizations.map {
            WorkspaceSummary(id: $0.id, name: $0.name, slug: $0.slug)
        }
    }

    /// Exchanges the account credential for a short-lived token scoped to one workspace.
    /// The session transport will consume this token; it is never persisted with the login token.
    func streamsAccess(workspaceID: WorkspaceSummary.ID) async throws -> StreamsAccess {
        guard account != nil, let accountToken = tokenStore.read() else {
            throw LodyClientError.signedOut
        }
        if let cached = streamsAccessCache[workspaceID],
           cached.accountToken == accountToken,
           cached.expiresAt > Date() {
            return cached.access
        }
        let generation = authenticationGeneration
        let requestedAt = Date()
        let data = try await send(
            path: "api/loro-streams/token",
            method: "POST",
            json: StreamsTokenRequest(workspaceId: workspaceID),
            token: accountToken
        )
        guard generation == authenticationGeneration, tokenStore.read() == accountToken else {
            throw LodyClientError.signedOut
        }
        let response = try JSONDecoder().decode(StreamsTokenResponse.self, from: data)
        guard !response.token.isEmpty, response.expiresIn > 0 else {
            throw LodyClientError.notConnected
        }
        let gatewayBaseURL: URL?
        if let rawURL = response.gatewayBaseUrl {
            guard let url = URL(string: rawURL), url.scheme == "https", url.host != nil else {
                throw LodyClientError.notConnected
            }
            gatewayBaseURL = url
        } else {
            gatewayBaseURL = nil
        }
        let access = StreamsAccess(
            token: response.token,
            expiresIn: response.expiresIn,
            gatewayBaseURL: gatewayBaseURL,
            shardHostSuffix: response.shardHostSuffix
        )
        streamsAccessCache[workspaceID] = (
            access,
            requestedAt.addingTimeInterval(max(0, response.expiresIn - min(30, response.expiresIn * 0.1))),
            accountToken
        )
        return access
    }

    func sessions(workspaceID: WorkspaceSummary.ID) async throws -> [SessionSummary] {
        try Task.checkCancellation()
        let generation = authenticationGeneration
        let access = try await streamsAccess(workspaceID: workspaceID)
        try Task.checkCancellation()
        let bridge = sessionBridge ?? makeSessionBridge()
        sessionBridge = bridge
        let sessions = try await bridge.sessions(workspaceID: workspaceID, access: access)
        try Task.checkCancellation()
        guard generation == authenticationGeneration, account != nil else {
            throw LodyClientError.signedOut
        }
        return sessions
    }

    func conversation(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> Conversation {
        try Task.checkCancellation()
        let generation = authenticationGeneration
        let access = try await streamsAccess(workspaceID: workspaceID)
        try Task.checkCancellation()
        let bridge = sessionBridge ?? makeSessionBridge()
        sessionBridge = bridge
        let conversation = try await bridge.conversation(
            sessionID: sessionID,
            workspaceID: workspaceID,
            access: access
        )
        try Task.checkCancellation()
        guard generation == authenticationGeneration, account != nil else {
            throw LodyClientError.signedOut
        }
        return conversation
    }

    func loadSessionImage(
        workspaceID: WorkspaceSummary.ID,
        sessionID: SessionSummary.ID,
        imageID: String,
        variant: SessionImageVariant
    ) async throws -> Data {
        try Task.checkCancellation()
        guard account != nil, let token = tokenStore.read(), !token.isEmpty else {
            throw LodyClientError.signedOut
        }
        let generation = authenticationGeneration
        let key = SessionImageCacheKey(
            credentialID: Self.credentialID(token, baseURL: baseURL),
            workspaceID: workspaceID,
            sessionID: sessionID,
            imageID: imageID,
            variant: variant
        )
        if let cached = sessionImageCache[key] { return cached }
        let waiterID = UUID()
        let data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if sessionImageLoads[key] != nil {
                    sessionImageLoads[key]?.waiters[waiterID] = continuation
                    return
                }
                let loadID = UUID()
                let task = Task { [session, imageBaseURL, weak self] in
                    let result: Result<Data, Error>
                    do {
                        let data = try await SessionImageTransport.load(
                            session: session, baseURL: imageBaseURL, workspaceID: workspaceID, sessionID: sessionID,
                            imageID: imageID, variant: variant, token: token
                        )
                        result = .success(data)
                    } catch {
                        result = .failure(error)
                    }
                    self?.finishSessionImageLoad(result, key: key, loadID: loadID, generation: generation, token: token)
                }
                sessionImageLoads[key] = SessionImageLoad(id: loadID, task: task, waiters: [waiterID: continuation])
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelSessionImageWaiter(waiterID, key: key) }
        }
        try Task.checkCancellation()
        guard generation == authenticationGeneration, account != nil, tokenStore.read() == token else {
            throw LodyClientError.signedOut
        }
        return data
    }

    private func cancelSessionImageWaiter(_ waiterID: UUID, key: SessionImageCacheKey) {
        guard let waiter = sessionImageLoads[key]?.waiters.removeValue(forKey: waiterID) else { return }
        waiter.resume(throwing: CancellationError())
        if sessionImageLoads[key]?.waiters.isEmpty == true {
            sessionImageLoads.removeValue(forKey: key)?.task.cancel()
        }
    }

    private func finishSessionImageLoad(
        _ result: Result<Data, Error>, key: SessionImageCacheKey, loadID: UUID, generation: Int, token: String
    ) {
        // A cancelled load may finish after a new request for the same image starts.
        guard sessionImageLoads[key]?.id == loadID,
              let load = sessionImageLoads.removeValue(forKey: key) else { return }
        let validated: Result<Data, Error>
        if generation == authenticationGeneration, account != nil, tokenStore.read() == token {
            validated = result
            if case .success(let data) = result { storeSessionImage(data, for: key) }
        } else {
            validated = .failure(LodyClientError.signedOut)
        }
        for waiter in load.waiters.values { waiter.resume(with: validated) }
    }

    private func storeSessionImage(_ data: Data, for key: SessionImageCacheKey) {
        sessionImageCache[key] = data
        sessionImageOrder.removeAll { $0 == key }
        sessionImageOrder.append(key)
        while sessionImageOrder.count > 24 {
            sessionImageCache.removeValue(forKey: sessionImageOrder.removeFirst())
        }
    }

    private func makeSessionBridge() -> SessionSyncBridge {
        SessionSyncBridge { [weak self] workspaceID, refresh in
            guard let self else { throw LodyClientError.signedOut }
            if refresh { streamsAccessCache.removeValue(forKey: workspaceID) }
            return try await streamsAccess(workspaceID: workspaceID)
        }
    }

    func observeConversation(sessionID: String, workspaceID: String) async throws -> AsyncThrowingStream<ConversationUpdate, Error> {
        let generation = authenticationGeneration
        let access = try await streamsAccess(workspaceID: workspaceID)
        try Task.checkCancellation()
        guard generation == authenticationGeneration, account != nil else { throw LodyClientError.signedOut }
        let bridge = sessionBridge ?? makeSessionBridge()
        sessionBridge = bridge
        return bridge.observeConversation(sessionID: sessionID, workspaceID: workspaceID, access: access)
    }

    @discardableResult
    func send(
        _ text: String,
        runConfig: RunConfigChoice?,
        sessionID: SessionSummary.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> RunConfigChoice? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LodyClientError.emptyMessage }
        guard let userID = account?.id, !userID.isEmpty else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        let key = SendKey(userID: userID, workspaceID: workspaceID, sessionID: sessionID)
        if let pending = pendingSends[key], pending.text != trimmed {
            throw LodyClientError.previousSendPending(pending.text)
        }
        // A retry resumes the original turn, including the configuration it was authored with.
        let pending = pendingSends[key] ?? PendingSend(
            text: trimmed, turnID: UUID().uuidString.lowercased(), runConfig: runConfig
        )
        let turnID = pending.turnID
        pendingSends[key] = pending
        let access = try await streamsAccess(workspaceID: workspaceID)
        try Task.checkCancellation()
        let bridge = sessionBridge ?? makeSessionBridge()
        sessionBridge = bridge
        let result = try await bridge.sendText(trimmed, turnID: turnID, userID: userID,
                                               runConfig: pending.runConfig,
                                               sessionID: sessionID, workspaceID: workspaceID, access: access)
        guard generation == authenticationGeneration, account != nil else {
            throw LodyClientError.signedOut
        }
        if result == "busy" {
            if pendingSends[key]?.turnID == turnID { pendingSends.removeValue(forKey: key) }
            throw LodyClientError.sessionBusy
        }
        if result == "superseded" {
            if pendingSends[key]?.turnID == turnID { pendingSends.removeValue(forKey: key) }
            throw LodyClientError.sendSuperseded
        }
        guard result == "sent" else { throw LodyClientError.deliveryUnconfirmed }
        if pendingSends[key]?.turnID == turnID { pendingSends.removeValue(forKey: key) }
        return pending.runConfig
    }

    func newSessionOptions(
        templateSessionID: SessionSummary.ID,
        agentConfigID: String?,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> NewSessionOptions {
        guard account != nil else { throw LodyClientError.signedOut }
        let generation = authenticationGeneration
        let access = try await streamsAccess(workspaceID: workspaceID)
        try Task.checkCancellation()
        let bridge = sessionBridge ?? makeSessionBridge()
        sessionBridge = bridge
        let options = try await bridge.newSessionOptions(
            templateSessionID: templateSessionID, agentConfigID: agentConfigID,
            workspaceID: workspaceID, access: access
        )
        guard generation == authenticationGeneration, account != nil else { throw LodyClientError.signedOut }
        return options
    }

    func startSession(
        _ text: String,
        agentConfigID: String?,
        selections: [RunConfigChoice],
        projectID: String,
        templateSessionID: SessionSummary.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> SessionSummary.ID {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LodyClientError.emptyMessage }
        guard let userID = account?.id, !userID.isEmpty else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        // An unconfirmed start may already exist remotely. Resume it rather
        // than creating a second session with different text.
        let key = StartKey(userID: userID, workspaceID: workspaceID, projectID: projectID)
        if let pending = pendingStarts[key], pending.text != trimmed {
            throw LodyClientError.previousSendPending(pending.text)
        }
        try Task.checkCancellation()
        // A second replica can append the same business ID before either write
        // syncs. Keep this lock through bridge teardown, even across page changes.
        guard activeStarts[key] == nil else { throw LodyClientError.deliveryUnconfirmed }
        let operationID = UUID()
        activeStarts[key] = operationID
        defer {
            if activeStarts[key] == operationID { activeStarts.removeValue(forKey: key) }
        }
        // A retry keeps the agent and configuration it was first authored with.
        let pending = pendingStarts[key] ?? PendingStart(
            text: trimmed, sessionID: UUID().uuidString.lowercased(),
            turnID: UUID().uuidString.lowercased(), agentConfigID: agentConfigID, selections: selections
        )
        pendingStarts[key] = pending
        let access = try await streamsAccess(workspaceID: workspaceID)
        try Task.checkCancellation()
        guard generation == authenticationGeneration, account != nil else { throw LodyClientError.signedOut }
        let bridge = sessionBridge ?? makeSessionBridge()
        sessionBridge = bridge
        let result = try await bridge.startSession(
            trimmed, sessionID: pending.sessionID, turnID: pending.turnID, userID: userID,
            agentConfigID: pending.agentConfigID, selections: pending.selections,
            templateSessionID: templateSessionID,
            workspaceID: workspaceID, access: access
        )
        guard generation == authenticationGeneration, account != nil else { throw LodyClientError.signedOut }
        if result == "rejected" {
            if pendingStarts[key]?.sessionID == pending.sessionID { pendingStarts.removeValue(forKey: key) }
            throw LodyClientError.sessionCreationRejected
        }
        guard result == "sent" else { throw LodyClientError.deliveryUnconfirmed }
        if pendingStarts[key]?.sessionID == pending.sessionID { pendingStarts.removeValue(forKey: key) }
        return pending.sessionID
    }

    func cancelSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
        guard account != nil else { throw LodyClientError.signedOut }
        let generation = authenticationGeneration
        let access = try await streamsAccess(workspaceID: workspaceID)
        try Task.checkCancellation()
        guard generation == authenticationGeneration, account != nil else { throw LodyClientError.signedOut }
        let bridge = sessionBridge ?? makeSessionBridge()
        sessionBridge = bridge
        let result = try await bridge.cancelSession(sessionID: sessionID, workspaceID: workspaceID, access: access)
        guard generation == authenticationGeneration, account != nil else { throw LodyClientError.signedOut }
        switch result {
        case "requested": return
        case "unavailable": throw LodyClientError.sessionBusy
        default: throw LodyClientError.deliveryUnconfirmed
        }
    }

    @discardableResult
    func archiveSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> [SessionSummary.ID] {
        guard account != nil else { throw LodyClientError.signedOut }
        let generation = authenticationGeneration
        let access = try await streamsAccess(workspaceID: workspaceID)
        try Task.checkCancellation()
        guard generation == authenticationGeneration, account != nil else { throw LodyClientError.signedOut }
        let bridge = sessionBridge ?? makeSessionBridge()
        sessionBridge = bridge
        let result = try await bridge.archiveSession(
            sessionID: sessionID, workspaceID: workspaceID, access: access
        )
        guard generation == authenticationGeneration, account != nil else { throw LodyClientError.signedOut }
        switch result.status {
        case "archived": return result.sessionIDs
        case "missing": throw LodyClientError.sessionMissing
        default: throw LodyClientError.deliveryUnconfirmed
        }
    }

    func archivedSessions(workspaceID: WorkspaceSummary.ID) async throws -> [ArchivedSessionSummary] {
        try Task.checkCancellation()
        let generation = authenticationGeneration
        let access = try await streamsAccess(workspaceID: workspaceID)
        try Task.checkCancellation()
        let bridge = sessionBridge ?? makeSessionBridge()
        sessionBridge = bridge
        let sessions = try await bridge.archivedSessions(workspaceID: workspaceID, access: access)
        try Task.checkCancellation()
        guard generation == authenticationGeneration, account != nil else {
            throw LodyClientError.signedOut
        }
        return sessions
    }

    func restoreArchivedSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
        let result = try await mutateArchivedSession(workspaceID: workspaceID) { bridge, access in
            try await bridge.restoreArchivedSession(sessionID: sessionID, workspaceID: workspaceID, access: access)
        }
        switch result {
        case "restored": return
        case "project-missing": throw LodyClientError.archivedProjectUnavailable
        case "missing": throw LodyClientError.sessionMissing
        default: throw LodyClientError.deliveryUnconfirmed
        }
    }

    func deleteArchivedSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
        let result = try await mutateArchivedSession(workspaceID: workspaceID) { bridge, access in
            try await bridge.deleteArchivedSession(sessionID: sessionID, workspaceID: workspaceID, access: access)
        }
        switch result {
        case "deleted", "missing": return
        case "not-archived": throw LodyClientError.sessionMissing
        default: throw LodyClientError.deliveryUnconfirmed
        }
    }

    private func mutateArchivedSession(
        workspaceID: WorkspaceSummary.ID,
        operation: (SessionSyncBridge, StreamsAccess) async throws -> String
    ) async throws -> String {
        guard account != nil else { throw LodyClientError.signedOut }
        let generation = authenticationGeneration
        let access = try await streamsAccess(workspaceID: workspaceID)
        try Task.checkCancellation()
        guard generation == authenticationGeneration, account != nil else { throw LodyClientError.signedOut }
        let bridge = sessionBridge ?? makeSessionBridge()
        sessionBridge = bridge
        let result = try await operation(bridge, access)
        guard generation == authenticationGeneration, account != nil else { throw LodyClientError.signedOut }
        return result
    }

    func respond(
        _ decision: PermissionDecision,
        requestID: PermissionPrompt.ID,
        sessionID: SessionSummary.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws {
        throw LodyClientError.notConnected
    }

    private func url(path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/" + path
        return components?.url ?? baseURL
    }

    private func loadAccount(token: String) async throws -> Account {
        let data = try await send(path: "api/auth/get-session", method: "GET", json: Optional<String>.none, token: token)
        if data == Data("null".utf8) { throw LodyClientError.signedOut }
        let session = try JSONDecoder().decode(SessionResponse.self, from: data)
        guard let email = session.user?.email, !email.isEmpty else { throw LodyClientError.signInFailed }
        return Account(email: email, id: session.user?.id)
    }

    private func perform(
        path: String,
        method: String,
        json: (some Encodable)?,
        token: String?,
        acceptAnyStatus: Bool
    ) async throws -> (Int, Data) {
        let (status, data) = try await request(path: path, method: method, json: json, token: token)
        if status >= 500 {
            #if DEBUG
            print("Kurage Lody HTTP failure: \(method) /\(path) status=\(status)")
            #endif
        }
        if acceptAnyStatus || (200..<300).contains(status) {
            return (status, data)
        }
        throw errorCode(status: status)
    }

    private func send<Body: Encodable>(
        path: String,
        method: String,
        json: Body?,
        token: String?
    ) async throws -> Data {
        let (_, data) = try await perform(
            path: path,
            method: method,
            json: json,
            token: token,
            acceptAnyStatus: false
        )
        return data
    }

    private func request<Body: Encodable>(
        path: String,
        method: String,
        json: Body?,
        token: String?
    ) async throws -> (Int, Data) {
        var request = URLRequest(url: url(path: path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(LodyEndpoints.webOrigin, forHTTPHeaderField: "Origin")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(json)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            #if DEBUG
            let networkError = error as NSError
            print("Kurage Lody transport failure: \(method) /\(path) domain=\(networkError.domain) code=\(networkError.code)")
            #endif
            throw LodyClientError.unreachable
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw LodyClientError.signInFailed }
        return (http.statusCode, data)
    }

    private func errorCode(status: Int) -> LodyClientError {
        if status == 401 {
            return .signedOut
        }
        if status >= 500 {
            return .unreachable
        }
        return .signInFailed
    }

    private static func authorizationPage(_ raw: String) throws -> URL {
        guard var components = URLComponents(string: raw),
              components.scheme == "https",
              let host = components.host?.lowercased(),
              host == "lody.ai" || host == "backend.lody.ai",
              components.user == nil,
              components.password == nil
        else {
            throw LodyClientError.signInFailed
        }
        components.host = "lody.ai"
        guard let url = components.url else { throw LodyClientError.signInFailed }
        return url
    }

    private func decodeOrganizations(_ data: Data) throws -> [OrganizationBody] {
        if let list = try? JSONDecoder().decode([OrganizationBody].self, from: data) {
            return list
        }
        if let wrapped = try? JSONDecoder().decode(OrganizationListBody.self, from: data) {
            return wrapped.organizations ?? wrapped.data ?? []
        }
        throw LodyClientError.signInFailed
    }
}

private struct DeviceCodeRequest: Encodable {
    var clientID: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

private struct DeviceCodeBody: Decodable {
    var deviceCode: String
    var userCode: String
    var verificationURIComplete: String
    var expiresIn: TimeInterval
    var interval: TimeInterval

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct DeviceTokenRequest: Encodable {
    var clientID: String
    var deviceCode: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case deviceCode = "device_code"
        case grantType = "grant_type"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientID, forKey: .clientID)
        try container.encode(deviceCode, forKey: .deviceCode)
        try container.encode("urn:ietf:params:oauth:grant-type:device_code", forKey: .grantType)
    }
}

private struct DeviceTokenBody: Decodable {
    var accessToken: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case error
    }
}

private struct SessionResponse: Decodable {
    var user: AuthUserBody?
}

private struct AuthUserBody: Decodable {
    var id: String?
    var email: String?
}

private struct OrganizationBody: Decodable {
    var id: String
    var name: String
    var slug: String
}

private struct OrganizationListBody: Decodable {
    var organizations: [OrganizationBody]?
    var data: [OrganizationBody]?
}

struct StreamsAccess: Equatable, Sendable {
    let token: String
    let expiresIn: TimeInterval
    let gatewayBaseURL: URL?
    let shardHostSuffix: String?
}

private struct StreamsTokenRequest: Encodable {
    let workspaceId: String
}

private struct StreamsTokenResponse: Decodable {
    let token: String
    let expiresIn: TimeInterval
    let gatewayBaseUrl: String?
    let shardHostSuffix: String?
}

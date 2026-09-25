import Foundation
import Testing
@testable import Kurage

@MainActor
@Suite(.serialized)
struct ConversationImageTests {
    @Test func textOnlyTurnsRemainReadableWithoutImageParts() throws {
        let turn = ConversationTurn(id: "a", author: .agent, text: "Hello")
        #expect(turn.content == [.text("Hello")])
        let decoded = try JSONDecoder().decode(
            ConversationTurn.self,
            from: Data(#"{"id":"a","author":"user","text":"Hi"}"#.utf8)
        )
        #expect(decoded.content == [.text("Hi")])
    }

    @Test func patchKeepsImageOrderAndDropsUndisplayableParts() throws {
        let previous = Conversation(sessionID: "s", turns: [
            ConversationTurn(id: "a", author: .agent, text: "See"),
        ], permission: nil)
        let patch = try JSONDecoder().decode(ConversationPatch.self, from: Data("""
        {"sessionID":"s","order":["a"],"changed":[{"id":"a","author":"agent","text":"See","parts":[
          {"type":"text","text":"See"},
          {"type":"image","imageID":"shot","mimeType":"image/png","fileName":"diff.png","width":4,"height":2},
          {"type":"image","imageID":"unlabeled","fileName":"photo.png"},
          {"type":"image","imageID":"vector","mimeType":"image/svg+xml"},
          {"type":"tool_call","text":"hidden"}
        ]}],"permission":null,"activity":"idle","syncState":"live"}
        """.utf8))
        let update = try patch.applying(to: previous)
        #expect(update.conversation.turns == [
            ConversationTurn(id: "a", author: .agent, text: "See", parts: [
                .text("See"),
                .image(ConversationImage(
                    imageID: "shot", mimeType: "image/png", fileName: "diff.png", width: 4, height: 2
                )),
                .image(ConversationImage(imageID: "unlabeled", mimeType: nil, fileName: "photo.png")),
            ]),
        ])
    }

    @Test func userImagesSitAboveTextAndAgentImagesStayInOrder() {
        let shot = ConversationImage(imageID: "shot", mimeType: "image/png")
        let other = ConversationImage(imageID: "other", mimeType: "image/jpeg")
        #expect(conversationBlocks(author: .user, content: [
            .text("Look"), .image(shot), .text("Again"),
        ]) == [
            .images(id: "images", images: [shot]),
            .text(id: "text", text: "Look\n\nAgain"),
        ])
        #expect(conversationBlocks(author: .agent, content: [
            .text("Before"), .image(shot), .image(other), .text("After"),
        ]) == [
            .text(id: "text-0", text: "Before"),
            .images(id: "images-1", images: [shot, other]),
            .text(id: "text-2", text: "After"),
        ])
    }

    @Test func imageURLUsesStorageSessionAndThumbnailQuery() throws {
        let url = try #require(SessionImageTransport.url(
            baseURL: LodyEndpoints.cloudAPIBaseURL,
            workspaceID: "work id",
            sessionID: "session id",
            imageID: "image-id",
            variant: .inline
        ))
        #expect(url.absoluteString == "https://api.lody.ai/api/workspaces/work%20id/session-images/session%20id/image-id/thumbnail?width=768&fit=scale-down&quality=85")
    }

    @Test func imageBytesMustMatchAnAllowedImage() {
        #expect(SessionImageTransport.validatedImage(FixtureImage.png, contentType: "image/png") == FixtureImage.png)
        #expect(SessionImageTransport.validatedImage(Data("not an image".utf8), contentType: "image/png") == nil)
        #expect(SessionImageTransport.validatedImage(FixtureImage.png, contentType: "text/html") == nil)
        var oversized = FixtureImage.png
        oversized.append(Data(count: SessionImageTransport.maxBytes))
        #expect(SessionImageTransport.validatedImage(oversized, contentType: "image/png") == nil)
    }

    @Test func redirectKeepsAuthorizationOnlyOnTheImageHost() throws {
        let sameHost = URLRequest(url: URL(string: "https://api.lody.ai/api/workspaces/w/session-images/s/i")!)
        let followed = try #require(SessionImageRedirect.request(
            sameHost, allowedHost: "api.lody.ai", authorization: "Bearer secret"
        ))
        #expect(followed.value(forHTTPHeaderField: "Authorization") == "Bearer secret")

        let foreign = URLRequest(url: URL(string: "https://evil.example/image")!)
        #expect(SessionImageRedirect.request(foreign, allowedHost: "api.lody.ai", authorization: "Bearer secret") == nil)
        let authHost = URLRequest(url: URL(string: "https://backend.lody.ai/image")!)
        #expect(SessionImageRedirect.request(authHost, allowedHost: "api.lody.ai", authorization: "Bearer secret") == nil)
        let downgrade = URLRequest(url: URL(string: "http://api.lody.ai/image")!)
        #expect(SessionImageRedirect.request(downgrade, allowedHost: "api.lody.ai", authorization: "Bearer secret") == nil)
        let credentials = URLRequest(url: URL(string: "https://user:pass@api.lody.ai/image")!)
        #expect(SessionImageRedirect.request(credentials, allowedHost: "api.lody.ai", authorization: "Bearer secret") == nil)
    }

    @Test func liveClientDownloadsThumbnailsAndFallsBackToTheOriginal() async throws {
        let store = ImageTokenStore()
        _ = store.write("account-token")
        let log = ImageRequestLog()
        log.install { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/thumbnail") {
                return (404, "text/plain", Data())
            }
            return (200, "image/png", FixtureImage.png)
        }
        let client = HTTPLodyClient(
            session: log.session, tokenStore: store, baseURL: log.baseURL, cacheURL: isolatedCacheURL
        )
        _ = try #require(await client.restoreSession())
        log.resetCount()
        let data = try await client.loadSessionImage(
            workspaceID: "work id", sessionID: "fork-session", imageID: "shot", variant: .inline
        )
        #expect(data == FixtureImage.png)
        #expect(log.imageRequests == 2)
        #expect(log.authorizations == ["Bearer account-token", "Bearer account-token"])
        #expect(log.urls.contains { $0.contains("https://api.lody.ai/api/workspaces/work%20id/session-images/fork-session/shot/thumbnail?width=768&fit=scale-down&quality=85") })
        #expect(log.urls.contains { $0 == "https://api.lody.ai/api/workspaces/work%20id/session-images/fork-session/shot" })
        log.resetCount()
        let cached = try await client.loadSessionImage(
            workspaceID: "work id", sessionID: "fork-session", imageID: "shot", variant: .inline
        )
        #expect(cached == FixtureImage.png)
        #expect(log.imageRequests == 0)

        client.signOut()
        await #expect(throws: LodyClientError.signedOut) {
            try await client.loadSessionImage(
                workspaceID: "work id", sessionID: "fork-session", imageID: "shot", variant: .original
            )
        }
    }

    @Test(.timeLimit(.minutes(1))) func cancellingOneWaiterKeepsTheSharedDownload() async throws {
        let (started, startedSignal) = AsyncStream<Void>.makeStream()
        let pending = DeferredImageRequestBox()
        DeferredImageURLProtocol.onStart = { pending.capture($0); startedSignal.yield(()) }
        defer { DeferredImageURLProtocol.onStart = nil }
        let client = try await deferredImageClient()
        var requests = started.makeAsyncIterator()
        let first = Task { try await self.loadImage(client) }
        _ = await requests.next()
        let request = try #require(pending.current())
        let (joined, joinedSignal) = AsyncStream<Void>.makeStream()
        let second = Task {
            joinedSignal.yield(())
            return try await self.loadImage(client)
        }
        var joins = joined.makeAsyncIterator()
        _ = await joins.next()
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        request.succeed()
        #expect(try await second.value == FixtureImage.png)
    }

    @Test(.timeLimit(.minutes(1))) func cancellingLastWaiterStopsDownloadAndAllowsANewRequest() async throws {
        let (started, startedSignal) = AsyncStream<Void>.makeStream()
        let pending = DeferredImageRequestBox()
        let (stopped, stoppedSignal) = AsyncStream<Void>.makeStream()
        DeferredImageURLProtocol.onStart = { pending.capture($0); startedSignal.yield(()) }
        DeferredImageURLProtocol.onStop = { stoppedSignal.yield(()) }
        defer {
            DeferredImageURLProtocol.onStart = nil
            DeferredImageURLProtocol.onStop = nil
        }
        let client = try await deferredImageClient()
        var requests = started.makeAsyncIterator()
        var cancellations = stopped.makeAsyncIterator()
        let first = Task { try await self.loadImage(client) }
        _ = await requests.next()
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        _ = await cancellations.next()

        let replacement = Task { try await self.loadImage(client) }
        _ = await requests.next()
        let request = try #require(pending.current())
        #expect(request.request.url?.path.hasSuffix("/thumbnail") == true)
        request.succeed()
        #expect(try await replacement.value == FixtureImage.png)
    }

    @Test(.timeLimit(.minutes(1))) func signOutReleasesImageWaiters() async throws {
        let (started, startedSignal) = AsyncStream<Void>.makeStream()
        let pending = DeferredImageRequestBox()
        DeferredImageURLProtocol.onStart = { pending.capture($0); startedSignal.yield(()) }
        defer { DeferredImageURLProtocol.onStart = nil }
        let client = try await deferredImageClient()
        var requests = started.makeAsyncIterator()
        let load = Task { try await self.loadImage(client) }
        _ = await requests.next()
        client.signOut()
        await #expect(throws: LodyClientError.signedOut) { try await load.value }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func oversizedImageStopsBeforeTheResponseFinishes(declaredLength: Bool) async throws {
        let (started, startedSignal) = AsyncStream<Void>.makeStream()
        let pending = DeferredImageRequestBox()
        let (stopped, stoppedSignal) = AsyncStream<Void>.makeStream()
        DeferredImageURLProtocol.onStart = { pending.capture($0); startedSignal.yield(()) }
        DeferredImageURLProtocol.onStop = { stoppedSignal.yield(()) }
        defer {
            DeferredImageURLProtocol.onStart = nil
            DeferredImageURLProtocol.onStop = nil
        }
        let client = try await deferredImageClient()
        var requests = started.makeAsyncIterator()
        var cancellations = stopped.makeAsyncIterator()
        let load = Task {
            try await client.loadSessionImage(workspaceID: "workspace", sessionID: "chat",
                                              imageID: "large", variant: .original)
        }
        _ = await requests.next()
        let request = try #require(pending.current())
        request.beginImage(length: declaredLength ? SessionImageTransport.maxBytes + 1 : nil)
        if declaredLength {
            // URLProtocol/AsyncBytes buffers small chunks before handing off
            // the response. This is still far below the declared size/limit.
            request.send(Data(count: 32 * 1024))
        } else {
            request.send(Data(count: SessionImageTransport.maxBytes / 2))
            request.send(Data(count: SessionImageTransport.maxBytes / 2 + 1))
        }
        // No completion is sent: rejecting only after the body finishes would hang.
        await #expect(throws: LodyClientError.notConnected) { try await load.value }
        _ = await cancellations.next()
    }

    private func loadImage(_ client: HTTPLodyClient) async throws -> Data {
        try await client.loadSessionImage(workspaceID: "workspace", sessionID: "chat", imageID: "shot", variant: .inline)
    }

    private func deferredImageClient() async throws -> HTTPLodyClient {
        let store = ImageTokenStore()
        _ = store.write("account-token")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeferredImageURLProtocol.self]
        let client = HTTPLodyClient(session: URLSession(configuration: configuration), tokenStore: store,
                                    cacheURL: isolatedCacheURL)
        _ = try #require(await client.restoreSession())
        return client
    }

    private var isolatedCacheURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
}

private final class ImageRequestLog: @unchecked Sendable {
    let baseURL = URL(string: "https://backend.lody.ai")!
    private let lock = NSLock()
    private var recorded = 0
    private var recordedURLs: [String] = []
    private var recordedAuthorizations: [String] = []

    var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    var imageRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var urls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedURLs
    }

    var authorizations: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedAuthorizations
    }

    func resetCount() {
        lock.lock()
        recorded = 0
        recordedURLs = []
        recordedAuthorizations = []
        lock.unlock()
    }

    func install(_ handler: @escaping @Sendable (URLRequest) -> (Int, String, Data)) {
        ImageURLProtocol.handler = { [weak self] request in
            let path = request.url?.path ?? ""
            if path.contains("session-images") {
                self?.lock.lock()
                self?.recorded += 1
                self?.recordedURLs.append(request.url?.absoluteString ?? "")
                self?.recordedAuthorizations.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
                self?.lock.unlock()
            }
            if path.contains("get-session") {
                return (200, "application/json", Data(#"{"user":{"id":"user","email":"ada@lody.ai"}}"#.utf8))
            }
            return handler(request)
        }
    }
}

@MainActor
private final class ImageTokenStore: AuthTokenStore {
    private var token: String?

    func read() -> String? { token }

    func write(_ token: String) -> Bool {
        self.token = token
        return true
    }

    func delete() { token = nil }
}

private final class ImageURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, String, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result = Self.handler?(request) ?? (500, "text/plain", Data())
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://backend.lody.ai")!,
            statusCode: result.0,
            httpVersion: nil,
            headerFields: ["Content-Type": result.1]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.2)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class DeferredImageURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var onStart: (@Sendable (DeferredImageURLProtocol) -> Void)?
    nonisolated(unsafe) static var onStop: (@Sendable () -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path.contains("get-session") == true {
            respond(Data(#"{"user":{"id":"user","email":"ada@lody.ai"}}"#.utf8), type: "application/json")
        } else {
            Self.onStart?(self)
        }
    }
    override func stopLoading() { Self.onStop?() }
    func succeed() { respond(FixtureImage.png, type: "image/png") }
    func beginImage(length: Int?) {
        var headers = ["Content-Type": "image/png"]
        if let length { headers["Content-Length"] = String(length) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
    func send(_ data: Data) { client?.urlProtocol(self, didLoad: data) }

    private func respond(_ data: Data, type: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

// URLProtocol invokes callbacks off the main actor; protect its test handle.
private final class DeferredImageRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: DeferredImageURLProtocol?
    func capture(_ request: DeferredImageURLProtocol) {
        lock.lock()
        defer { lock.unlock() }
        self.request = request
    }
    func current() -> DeferredImageURLProtocol? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

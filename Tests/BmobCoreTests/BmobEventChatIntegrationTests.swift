import XCTest
@testable import BmobCore

/// Opt-in, live end-to-end test. Creates and then deletes one Chat record.
/// Supply BMOB_EVENT_CHAT_LIVE_TEST=1, BMOB_EVENT_APP_KEY and BMOB_EVENT_REST_KEY.
/// Run: swift test --filter BmobEventChatIntegrationTests
/// Credentials are read from the environment and are never stored in this file.
final class BmobEventChatIntegrationTests: XCTestCase {
    private var event: BmobEvent?
    private var createdObjectId: String?
    private var restSession: URLSession?
    private var ownsSDKState = false

    override func tearDown() async throws {
        event?.stop()
        event = nil
        defer { restSession?.invalidateAndCancel(); restSession = nil }
        do {
            if let objectId = createdObjectId {
                _ = try await restRequest(method: "DELETE", objectId: objectId)
                print("[realtime-chat] Deleted test record: \(objectId)")
                createdObjectId = nil
            }
        } catch {
            XCTFail("Failed to delete this test's Chat record \(createdObjectId ?? ""): \(error.localizedDescription)")
        }
        if ownsSDKState { await BmobManager.shared.reset() }
        try await super.tearDown()
    }

    @MainActor
    func testChatInsertPublishesTableUpdate() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["BMOB_EVENT_CHAT_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set BMOB_EVENT_CHAT_LIVE_TEST=1 and supply realtime test credentials")
        }
        let appKey = try XCTUnwrap(environment["BMOB_EVENT_APP_KEY"], "Missing BMOB_EVENT_APP_KEY")
        _ = try XCTUnwrap(environment["BMOB_EVENT_REST_KEY"], "Missing BMOB_EVENT_REST_KEY")
        ownsSDKState = true
        await BmobManager.shared.reset()
        try await Bmob.resetIODomain("http://io.codenow.cn:3010")
        try await Bmob.initialize(appKey: appKey)
        print("[realtime-chat] SDK initialized")

        let marker = "BmobSwiftRealtimeTest-" + UUID().uuidString
        let ready = expectation(description: "Chat updateTable subscription sent after Socket.IO readiness")
        let received = expectation(description: "Received updateTable event containing this test's unique content")
        let observer = ChatEventObserver(marker: marker, ready: ready, received: received)
        let event = BmobEvent()
        self.event = event
        event.autoReconnect = false
        event.delegate = observer
        event.listenTableChange(.updateTable, tableName: "Chat")
        event.start()
        await fulfillment(of: [ready], timeout: 20)
        if let error = observer.error { throw error }
        guard observer.isReady, event.isConnected else { throw BmobError.timeout }
        print("[realtime-chat] Connected and subscribed to Chat.updateTable")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        restSession = URLSession(configuration: config)
        let inserted = try await restRequest(method: "POST", fields: [
            "name": "BmobSwift SDK realtime test",
            "content": marker,
        ])
        let objectId = try XCTUnwrap(inserted["objectId"] as? String, "REST create response has no objectId")
        createdObjectId = objectId
        print("[realtime-chat] Created test record: \(objectId)")

        await fulfillment(of: [received], timeout: 30)
        if let error = observer.error { throw error }
        let message = try XCTUnwrap(observer.message, "No event matched this test's unique content")
        XCTAssertEqual(message.action, "updateTable")
        XCTAssertEqual(message.className, "Chat")
        XCTAssertEqual(message.objectId, objectId)
        XCTAssertEqual(message.data?["content"] as? String, marker)
        XCTAssertEqual(message.data?["name"] as? String, "BmobSwift SDK realtime test")
        print("[realtime-chat] Correlated event received; payload assertions executed")
    }

    private func restRequest(method: String, objectId: String? = nil,
                             fields: [String: String]? = nil) async throws -> [String: Any] {
        let environment = ProcessInfo.processInfo.environment
        let appKey = try XCTUnwrap(environment["BMOB_EVENT_APP_KEY"], "Missing BMOB_EVENT_APP_KEY")
        let restKey = try XCTUnwrap(environment["BMOB_EVENT_REST_KEY"], "Missing BMOB_EVENT_REST_KEY")
        var url = URL(string: "https://api.codenow.cn/1/classes/Chat")!
        if let objectId { url.appendPathComponent(objectId) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(appKey, forHTTPHeaderField: "X-Bmob-Application-Id")
        request.setValue(restKey, forHTTPHeaderField: "X-Bmob-REST-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let fields { request.httpBody = try JSONSerialization.data(withJSONObject: fields) }
        let session = try XCTUnwrap(restSession)
        let (data, urlResponse) = try await session.data(for: request)
        let response = try XCTUnwrap(urlResponse as? HTTPURLResponse)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard (200..<300).contains(response.statusCode), json["code"] == nil else {
            throw BmobError.serverError(code: json["code"] as? Int ?? response.statusCode,
                                       message: json["error"] as? String ?? "Chat REST request failed")
        }
        return json
    }
}

/// BmobEvent delivers these callbacks on the main queue; test assertions also run on MainActor.
private final class ChatEventObserver: BmobEventDelegate {
    let marker: String
    var ready: XCTestExpectation?
    var received: XCTestExpectation?
    var isReady = false
    var message: BmobEventMessage?
    var error: Error?

    init(marker: String, ready: XCTestExpectation, received: XCTestExpectation) {
        self.marker = marker
        self.ready = ready
        self.received = received
    }
    func bmobEventCanStartListen(_ event: BmobEvent) {
        isReady = true
        ready?.fulfill()
        ready = nil
    }
    func bmobEvent(_ event: BmobEvent, didReceiveMessage message: BmobEventMessage) {
        // Avoid matching another user's Chat update. Do not log the raw event or credentials.
        guard let data = try? JSONSerialization.data(withJSONObject: message.rawValue),
              String(decoding: data, as: UTF8.self).contains(marker), self.message == nil else { return }
        self.message = message
        received?.fulfill()
        received = nil
    }
    func bmobEvent(_ event: BmobEvent, didFailWithError error: Error) {
        self.error = error
        ready?.fulfill()
        ready = nil
        received?.fulfill()
        received = nil
    }
}

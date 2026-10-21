import XCTest
@testable import BmobCore

final class BmobEventTests: XCTestCase {
    private func envelope(_ text: String) throws -> (String, [String: String]) {
        XCTAssertTrue(text.hasPrefix("5:::"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.dropFirst(4).utf8)) as? [String: Any])
        let args = try XCTUnwrap(json["args"] as? [String])
        XCTAssertEqual(args.count, 1)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(args[0].utf8)) as? [String: String])
        return (try XCTUnwrap(json["name"] as? String), payload)
    }

    func testHandshakeURLsAndValidation() throws {
        let url = try BmobEventWire.handshakeURL("https://io.example.com:3010")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.path, "/socket.io/1/")
        XCTAssertEqual(url.port, 3010)
        XCTAssertNotNil(url.query)
        XCTAssertEqual(try BmobEventWire.socketURL("wss://io.example.com:3010", sid: "abc_123").absoluteString,
                       "wss://io.example.com:3010/socket.io/1/websocket/abc_123")
        XCTAssertEqual(try BmobEventWire.handshakeURL("io.example.com:3010").scheme, "http")
        let handshake = try BmobEventWire.handshake("abc_123:15:60:websocket,xhr-polling\n")
        XCTAssertEqual(handshake.sid, "abc_123")
        XCTAssertEqual(handshake.timeout, 15)
        for invalid in ["", "error", ":15:60:websocket", "abc:0:60:websocket", "abc:nan:60:websocket",
                        "abc:15:60:xhr-polling", "../abc:15:60:websocket"] {
            XCTAssertThrowsError(try BmobEventWire.handshake(invalid))
        }
        XCTAssertThrowsError(try BmobEventWire.handshakeURL("file:///tmp/io"))
    }

    func testWebSocketRequestPreservesSchemeAndLegacyOrigin() throws {
        let sid = "7YJlHL0tJkPZj6xL"
        for (domain, socketScheme, expectedOrigin) in [
            ("http://io.codenow.cn:3010", "ws", "http://io.codenow.cn:3010"),
            ("https://io.example.com:9443", "wss", "https://io.example.com:9443"),
            ("ws://io.example.com:3010", "ws", "http://io.example.com:3010"),
            ("wss://io.example.com", "wss", "https://io.example.com"),
        ] {
            let url = try BmobEventWire.socketURL(domain, sid: sid)
            let request = try BmobEventWire.socketRequest(url)
            XCTAssertEqual(request.url?.scheme, socketScheme)
            XCTAssertEqual(request.url?.path, "/socket.io/1/websocket/" + sid)
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), expectedOrigin)
            // Check the actual URLSession overload used in production, not only URLComponents.
            let session = URLSession(configuration: .ephemeral)
            let task = session.webSocketTask(with: request)
            XCTAssertEqual(task.originalRequest?.url, url)
            XCTAssertEqual(task.originalRequest?.value(forHTTPHeaderField: "Origin"), expectedOrigin)
            task.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
        }
        XCTAssertThrowsError(try BmobEventWire.socketRequest(URL(string: "http://io.example.com/socket.io/1/websocket/sid")!))
        XCTAssertThrowsError(try BmobEventWire.socketRequest(URL(string: "https://io.example.com/socket.io/1/websocket/sid")!))
    }

    func testHTTPHandshakeOpensMatchingWebSocketWithReturnedSID() async {
        for (domain, httpScheme, socketScheme) in [
            ("http://io.codenow.cn:3010", "http", "ws"),
            ("https://io.example.com:9443", "https", "wss"),
        ] {
            let transport = MockTransport()
            transport.handshakeResult = .success("7YJlHL0tJkPZj6xL:60:90:websocket")
            let event = BmobEvent(configuration: { (domain, "test-app") }, makeTransport: { transport })
            await open(event, transport)
            XCTAssertEqual(transport.handshakeURL?.scheme, httpScheme)
            XCTAssertEqual(transport.handshakeURL?.host, transport.socketURL?.host)
            XCTAssertEqual(transport.handshakeURL?.port, transport.socketURL?.port)
            XCTAssertEqual(URLComponents(url: transport.handshakeURL!, resolvingAgainstBaseURL: false)?.path, "/socket.io/1/")
            XCTAssertEqual(transport.socketURL?.scheme, socketScheme)
            XCTAssertEqual(transport.socketURL?.path, "/socket.io/1/websocket/7YJlHL0tJkPZj6xL")
            event.stop()
        }
    }

    // Explicit opt-in: contacts the public Socket.IO endpoint, sends no subscription or business data.
    func testLiveSocketIOConnection() async throws {
        guard ProcessInfo.processInfo.environment["BMOB_EVENT_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set BMOB_EVENT_LIVE_TEST=1 to test the public Socket.IO connection")
        }
        let event = BmobEvent(configuration: { ("http://io.codenow.cn:3010", "unused-no-subscriptions") },
                              makeTransport: { BmobEventURLSessionTransport() })
        defer { event.stop() }
        event.autoReconnect = false
        let spy = DelegateSpy()
        event.delegate = spy
        let connected = expectation(description: "Received Socket.IO connection packet from live server")
        spy.connected = { connected.fulfill() }
        spy.error = { error in XCTFail("Live connection failed: \(error)"); connected.fulfill() }
        event.connect()
        await fulfillment(of: [connected], timeout: 20)
        XCTAssertTrue(event.isConnected)
    }

    func testTableUpdateUsesRowObjectIdWhenTopLevelIdIsEmpty() {
        let message = BmobEventMessage(json: [
            "action": "updateTable", "tableName": "Chat", "objectId": "",
            "data": ["objectId": "new-chat-row", "content": "test"],
        ])
        XCTAssertEqual(message.objectId, "new-chat-row")
        XCTAssertEqual(message.rawValue["objectId"] as? String, "")
        let row = BmobEventMessage(json: [
            "action": "updateRow", "objectId": "top-level-row", "data": ["objectId": "data-row"],
        ])
        XCTAssertEqual(row.objectId, "top-level-row")
        XCTAssertNil(BmobEventMessage(json: ["objectId": ""]).objectId)
    }

    func testCustomIODomainPriorityValidationAndReset() async throws {
        let manager = BmobManager.shared
        await manager.reset()
        addTeardownBlock { await manager.reset() }

        // Configuration may be supplied before initialization.
        try await Bmob.resetIODomain("https://custom.example.com:9443")
        await manager.set(apid: "test-apid", appKey: "test-app")
        await manager.set(ioDomain: "http://server.example.com:3010")
        await manager.markReady()
        var config = try await manager.eventConfiguration()
        XCTAssertEqual(config.0, "https://custom.example.com:9443")
        XCTAssertEqual(config.1, "test-app")
        XCTAssertEqual(try BmobEventWire.socketURL(config.0, sid: "abc").scheme, "wss")

        // Subsequent init responses must not replace the user override.
        await manager.set(ioDomain: "http://new-server.example.com:3010")
        try await Bmob.resetIODomain("  wss://next.example.com  ")
        config = try await manager.eventConfiguration()
        XCTAssertEqual(config.0, "wss://next.example.com")
        XCTAssertEqual(try BmobEventWire.handshakeURL(config.0).scheme, "https")
        for invalid in ["", "   ", "file:///tmp/io", "https://", "http://io.example.com:70000",
                        "https://io.example.com/path", "https://io.example.com?query=1"] {
            do {
                try await Bmob.resetIODomain(invalid)
                XCTFail("Accepted invalid domain: \(invalid)")
            } catch {
                XCTAssertEqual((error as? BmobError)?.code, BmobError.invalidParameter(reason: "").code)
            }
            let unchanged = try await manager.eventConfiguration()
            XCTAssertEqual(unchanged.0, "wss://next.example.com")
        }
        try await Bmob.resetIODomain(nil)
        config = try await manager.eventConfiguration()
        XCTAssertEqual(config.0, "http://new-server.example.com:3010")

        await manager.reset()
        await manager.set(apid: "test-apid", appKey: "test-app")
        await manager.markReady()
        config = try await manager.eventConfiguration()
        XCTAssertEqual(config.0, "http://io.codenow.cn:3010")
    }

    func testAllActionsMatchLegacyProtocol() throws {
        for action in BmobActionType.allCases {
            for cancel in [false, true] {
                let text = try BmobEventWire.subscription(appKey: "test-app", action: action,
                    table: "消息\"表", objectId: "row1", cancel: cancel)
                let (name, payload) = try envelope(text)
                XCTAssertEqual(name, cancel ? "client_unsub" : "client_sub")
                XCTAssertEqual(payload, ["appKey": "test-app", "action": (cancel ? "unsub_" : "") + action.rawValue,
                                         "tableName": "消息\"表", "objectId": "row1"])
            }
        }
    }

    private func fixture(delay: TimeInterval = 5) -> (BmobEvent, MockTransport) {
        let transport = MockTransport()
        let event = BmobEvent(configuration: { ("https://io.example.com:3010", "test-app") },
                              makeTransport: { transport }, reconnectDelay: delay)
        return (event, transport)
    }

    private func open(_ event: BmobEvent, _ transport: MockTransport) async {
        let opened = expectation(description: "WebSocket opened")
        transport.opened = { opened.fulfill() }
        event.connect()
        event.connect()
        await fulfillment(of: [opened], timeout: 2)
        XCTAssertFalse(event.isConnected)
        XCTAssertEqual(transport.handshakeCount, 1)
    }

    func testReadinessSubscribeCancelHeartbeatAndDuplicateCalls() async throws {
        let (event, transport) = fixture()
        defer { event.disconnect() }
        let spy = DelegateSpy()
        event.delegate = spy
        let connected = expectation(description: "connected on main")
        let ready = expectation(description: "ready on main")
        spy.connected = { XCTAssertTrue(Thread.isMainThread); connected.fulfill() }
        spy.ready = { XCTAssertTrue(Thread.isMainThread); ready.fulfill() }
        event.listenTableChange(className: "Note")
        event.listenRowChange(.deleteRow, tableName: "Note", objectId: "row1")
        await open(event, transport)
        transport.deliver("1::")
        XCTAssertTrue(event.isConnected)
        XCTAssertTrue(transport.sent.isEmpty)
        transport.deliver(#"5:::{"name":"client_send_data","args":[]}"#)
        await fulfillment(of: [connected, ready], timeout: 2)
        XCTAssertEqual(transport.sent.count, 2)
        let subscriptions = try transport.sent.map(envelope)
        XCTAssertEqual(Set(subscriptions.compactMap { $0.1["action"] }), ["updateTable", "deleteRow"])
        event.listenTableChange(className: "Note")
        XCTAssertEqual(transport.sent.count, 2)
        event.cancelListenTableChange(className: "Note")
        XCTAssertEqual(try envelope(transport.sent.last!).1["action"], "unsub_updateTable")
        event.cancelListenRowChange(.deleteRow, tableName: "Note", objectId: "row1")
        XCTAssertEqual(try envelope(transport.sent.last!).0, "client_unsub")
        transport.deliver("2::")
        XCTAssertEqual(transport.sent.last, "2::")
        event.disconnect()
        XCTAssertFalse(event.isConnected)
        XCTAssertTrue(transport.closed)
    }

    func testStreamsCoexistWithDelegateAndFinishOnStop() async {
        let (event, transport) = fixture()
        let spy = DelegateSpy()
        event.delegate = spy
        var first = event.eventStream().makeAsyncIterator()
        var second = event.eventStream().makeAsyncIterator()
        let delivered = expectation(description: "delegate event")
        delivered.expectedFulfillmentCount = 2
        spy.message = { message in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(message.className, "Note")
            XCTAssertEqual(message.objectId, "row1")
            delivered.fulfill()
        }
        await open(event, transport)
        transport.deliver("1::")
        transport.deliver(#"5:::{"name":"client_send_data","args":[]}"#)
        transport.deliver(#"5:::{"name":"server_pub","args":["{\"action\":\"updateRow\",\"tableName\":\"Note\",\"data\":{\"objectId\":\"row1\",\"title\":\"a:b\"}}"]}"#)
        let a = await first.next()
        let b = await second.next()
        XCTAssertEqual(a?.data?["title"] as? String, "a:b")
        XCTAssertEqual(b?.action, "updateRow")
        transport.deliver(#"5:::{"name":"server_pub","args":[{"action":"deleteRow","tableName":"Note","objectId":"row1"}]}"#)
        await fulfillment(of: [delivered], timeout: 2)
        _ = await first.next()
        _ = await second.next()
        event.stop()
        let endA = await first.next()
        let endB = await second.next()
        XCTAssertNil(endA)
        XCTAssertNil(endB)
    }

    func testReconnectRestoresOnlyActiveSubscriptionsAndIgnoresOldCallbacks() async throws {
        let first = MockTransport()
        let second = MockTransport()
        var transports = [first, second]
        let event = BmobEvent(configuration: { ("io.example.com:3010", "test-app") },
                              makeTransport: { transports.removeFirst() }, reconnectDelay: 0.01)
        defer { event.stop() }
        event.listenTableChange(className: "Note")
        event.listenRowChange(className: "Note", objectId: "row1")
        var stream = event.eventStream().makeAsyncIterator()
        await open(event, first)
        first.deliver("1::")
        first.deliver(#"5:::{"name":"client_send_data","args":[]}"#)
        event.cancelListenRowChange(className: "Note", objectId: "row1")
        let reopened = expectation(description: "reconnect")
        second.opened = { reopened.fulfill() }
        let stale = first.receiver
        first.deliver("0::")
        await fulfillment(of: [reopened], timeout: 2)
        stale?(.failure(BmobError.timeout))
        second.deliver("1::")
        second.deliver(#"5:::{"name":"client_send_data","args":[]}"#)
        XCTAssertTrue(event.isConnected)
        XCTAssertEqual(second.sent.count, 1)
        XCTAssertEqual(try envelope(second.sent[0]).1["action"], "updateTable")
        second.deliver(#"5:::{"name":"server_pub","args":[{"action":"updateTable","tableName":"Note"}]}"#)
        let message = await stream.next()
        XCTAssertEqual(message?.action, "updateTable")
    }

    func testStopDuringHandshakeIgnoresCompletion() async {
        let (event, transport) = fixture()
        transport.delayHandshake = true
        let handshake = expectation(description: "handshake started")
        transport.handshaking = { handshake.fulfill() }
        event.start()
        await fulfillment(of: [handshake], timeout: 2)
        event.stop()
        transport.handshakeCompletion?(.success("abc:15:60:websocket"))
        XCTAssertNil(transport.socketURL)
        XCTAssertFalse(event.isConnected)
    }

    func testInvalidSubscriptionAndHandshakeFailureAreReported() async {
        let (event, transport) = fixture()
        event.autoReconnect = false
        let spy = DelegateSpy()
        event.delegate = spy
        let errors = expectation(description: "invalid argument and handshake error")
        errors.expectedFulfillmentCount = 3
        spy.error = { _ in errors.fulfill() }
        event.listenTableChange(.updateRow, tableName: "Note")
        event.listenRowChange(.deleteRow, tableName: "Note", objectId: "")
        transport.handshakeResult = .success("abc:15:60:xhr-polling")
        event.start()
        await fulfillment(of: [errors], timeout: 2)
        XCTAssertFalse(event.isConnected)
        XCTAssertTrue(transport.closed)
        XCTAssertNil(transport.socketURL)
    }

    func testSendFailureClosesConnectionAndReportsError() async {
        let (event, transport) = fixture()
        event.autoReconnect = false
        let spy = DelegateSpy()
        event.delegate = spy
        let failed = expectation(description: "send failure reported")
        spy.error = { _ in failed.fulfill() }
        event.listenTableChange(className: "Note")
        await open(event, transport)
        transport.sendError = BmobError.networkError(underlying: URLError(.networkConnectionLost))
        transport.deliver("1::")
        transport.deliver(#"5:::{"name":"client_send_data","args":[]}"#)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertFalse(event.isConnected)
        XCTAssertTrue(transport.closed)
        event.stop()
    }

    func testStopCancelsScheduledReconnect() async {
        let (event, transport) = fixture(delay: 0.03)
        await open(event, transport)
        transport.deliver("1::")
        transport.deliver("0::")
        let unexpectedOpen = expectation(description: "must not reconnect after stop")
        unexpectedOpen.isInverted = true
        transport.opened = { unexpectedOpen.fulfill() }
        event.stop()
        await fulfillment(of: [unexpectedOpen], timeout: 0.1)
        XCTAssertEqual(transport.handshakeCount, 1)
        XCTAssertFalse(event.isConnected)
    }

    func testConfigurationFailureIsReportedWithoutOpeningTransport() async {
        let event = BmobEvent(configuration: { throw BmobError.notInitialized },
                              makeTransport: { XCTFail("Should not open transport"); return MockTransport() })
        event.autoReconnect = false
        let spy = DelegateSpy()
        event.delegate = spy
        let failed = expectation(description: "not initialized")
        spy.error = { error in
            XCTAssertEqual((error as? BmobError)?.code, BmobError.notInitialized.code)
            failed.fulfill()
        }
        event.connect()
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertFalse(event.isConnected)
        event.stop()
    }

    func testCancelledPendingSubscriptionIsNotSent() async {
        let (event, transport) = fixture()
        defer { event.stop() }
        event.listenTableChange(className: "Note")
        event.cancelListenTableChange(className: "Note")
        await open(event, transport)
        transport.deliver("1::")
        transport.deliver(#"5:::{"name":"client_send_data","args":[]}"#)
        XCTAssertTrue(transport.sent.isEmpty)
    }
}

private final class MockTransport: BmobEventTransport {
    var opened: (() -> Void)?
    var handshaking: (() -> Void)?
    var handshakeCompletion: ((Result<String, Error>) -> Void)?
    var receiver: ((Result<String, Error>) -> Void)?
    var handshakeResult: Result<String, Error> = .success("abc:15:60:websocket")
    var delayHandshake = false
    var handshakeCount = 0
    var handshakeURL: URL?
    var socketURL: URL?
    var sent: [String] = []
    var closed = false
    var sendError: Error?

    func handshake(_ url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        handshakeURL = url
        handshakeCount += 1
        handshakeCompletion = completion
        handshaking?()
        if !delayHandshake { completion(handshakeResult) }
    }
    func open(_ url: URL) { socketURL = url; DispatchQueue.main.async { self.opened?() } }
    func receive(completion: @escaping (Result<String, Error>) -> Void) { receiver = completion }
    func deliver(_ text: String) { let callback = receiver; receiver = nil; callback?(.success(text)) }
    func send(_ text: String, completion: @escaping (Error?) -> Void) { sent.append(text); completion(sendError) }
    func close() { closed = true }
}

private final class DelegateSpy: BmobEventDelegate {
    var connected: (() -> Void)?
    var ready: (() -> Void)?
    var message: ((BmobEventMessage) -> Void)?
    var error: ((Error) -> Void)?
    func bmobEventDidConnect(_ event: BmobEvent) { connected?() }
    func bmobEventCanStartListen(_ event: BmobEvent) { ready?() }
    func bmobEvent(_ event: BmobEvent, didReceiveMessage message: BmobEventMessage) { self.message?(message) }
    func bmobEvent(_ event: BmobEvent, didFailWithError error: Error) { self.error?(error) }
}

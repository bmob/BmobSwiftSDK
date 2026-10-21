import Foundation

/// 与旧版 Objective-C SDK 相同的实时监听操作。
public enum BmobActionType: String, CaseIterable, Sendable {
    case updateTable, deleteTable, updateRow, deleteRow

    fileprivate var isRow: Bool { self == .updateRow || self == .deleteRow }
}

/// Bmob 实时数据监听，使用服务端的 Socket.IO 0.9 协议。
/// 先完成 `Bmob.initialize`，再调用 `connect()`。可在连接前登记订阅。
/// 代理回调在主队列执行；断线后默认自动重连并恢复订阅。
public final class BmobEvent {
    public static let shared = BmobEvent()
    public weak var delegate: BmobEventDelegate?

    public var isConnected: Bool { locked { connected } }
    public var autoReconnect: Bool {
        get { locked { reconnectEnabled } }
        set {
            locked {
                reconnectEnabled = newValue
                if !newValue, reconnectWork != nil {
                    reconnectWork?.cancel()
                    reconnectWork = nil
                    running = false
                }
            }
        }
    }

    private let lock = NSRecursiveLock()
    private var connected = false
    private var ready = false
    private var running = false
    private var reconnectEnabled = true
    private var generation = UUID()
    private var appKey = ""
    private var transport: BmobEventTransport?
    private var subscriptions: Set<Subscription> = []
    private var streams: [UUID: AsyncStream<BmobEventMessage>.Continuation] = [:]
    private var timeoutWork: DispatchWorkItem?
    private var timeoutID = UUID()
    private var reconnectWork: DispatchWorkItem?
    private var configurationTask: Task<Void, Never>?
    private var heartbeatTimeout: TimeInterval = 30
    private let configuration: () async throws -> (String, String)
    private let makeTransport: () -> BmobEventTransport
    private let reconnectDelay: TimeInterval

    public convenience init() {
        self.init(configuration: {
            try await BmobManager.shared.eventConfiguration()
        }, makeTransport: { BmobEventURLSessionTransport() })
    }

    // Injectable transport keeps protocol/lifecycle tests independent of live credentials.
    init(configuration: @escaping () async throws -> (String, String),
         makeTransport: @escaping () -> BmobEventTransport,
         reconnectDelay: TimeInterval = 5) {
        self.configuration = configuration
        self.makeTransport = makeTransport
        self.reconnectDelay = reconnectDelay
    }

    deinit {
        configurationTask?.cancel()
        timeoutWork?.cancel()
        reconnectWork?.cancel()
        transport?.close()
        for continuation in streams.values { continuation.finish() }
    }

    /// 启动连接；重复调用不会创建额外连接。
    public func connect() {
        locked {
            guard !running else { return }
            running = true
            beginConnection()
        }
    }

    public func start() { connect() }
    public func stop() { disconnect() }

    /// 主动停止，取消重连并结束事件流。保留订阅，供下次 connect 恢复。
    public func disconnect() {
        locked {
            let wasRunning = running
            running = false
            cleanup()
            for continuation in streams.values { continuation.finish() }
            streams.removeAll()
            if wasRunning { notify { $0.bmobEventDidDisconnect(self, error: nil) } }
        }
    }

    /// 默认监听表更新（包括表内数据变化）；删除事件请传 `.deleteTable`。
    public func listenTableChange(className: String) {
        listenTableChange(.updateTable, tableName: className)
    }
    public func cancelListenTableChange(className: String) {
        cancelListenTableChange(.updateTable, tableName: className)
    }
    public func listenRowChange(className: String, objectId: String) {
        listenRowChange(.updateRow, tableName: className, objectId: objectId)
    }
    public func cancelListenRowChange(className: String, objectId: String) {
        cancelListenRowChange(.updateRow, tableName: className, objectId: objectId)
    }
    public func listenTableChange(_ action: BmobActionType, tableName: String) {
        change(action, table: tableName, objectId: "", row: false, cancel: false)
    }
    public func cancelListenTableChange(_ action: BmobActionType, tableName: String) {
        change(action, table: tableName, objectId: "", row: false, cancel: true)
    }
    public func listenRowChange(_ action: BmobActionType, tableName: String, objectId: String) {
        change(action, table: tableName, objectId: objectId, row: true, cancel: false)
    }
    public func cancelListenRowChange(_ action: BmobActionType, tableName: String, objectId: String) {
        change(action, table: tableName, objectId: objectId, row: true, cancel: true)
    }

    /// 可与 delegate 同时使用，也支持多个消费者。主动 disconnect 时结束；重连期间保留。
    public func eventStream() -> AsyncStream<BmobEventMessage> {
        let id = UUID()
        return AsyncStream { continuation in
            locked { streams[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.locked { self?.streams.removeValue(forKey: id) }
            }
        }
    }

    private struct Subscription: Hashable {
        let action: BmobActionType
        let table: String
        let objectId: String
    }

    @discardableResult
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func notify(_ body: @escaping (BmobEventDelegate) -> Void) {
        DispatchQueue.main.async { [weak self] in
            if let delegate = self?.delegate { body(delegate) }
        }
    }

    private func change(_ action: BmobActionType, table: String, objectId: String, row: Bool, cancel: Bool) {
        locked {
            guard action.isRow == row, !table.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !row || !objectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                notify { $0.bmobEvent(self, didFailWithError: BmobError.invalidParameter(reason: "Invalid realtime action, tableName or objectId")) }
                return
            }
            let subscription = Subscription(action: action, table: table, objectId: objectId)
            let changed: Bool
            if cancel { changed = subscriptions.remove(subscription) != nil }
            else { changed = subscriptions.insert(subscription).inserted }
            if changed && ready { send(subscription, cancel: cancel) }
        }
    }

    private func beginConnection() {
        cleanup()
        let token = generation
        configurationTask = Task { [weak self, configuration] in
            do {
                let (domain, key) = try await configuration()
                guard !Task.isCancelled else { return }
                self?.locked {
                    guard let self, self.running, self.generation == token else { return }
                    do {
                        self.appKey = key
                        let url = try BmobEventWire.handshakeURL(domain)
                        let transport = self.makeTransport()
                        self.transport = transport
                        self.armTimeout(30, token: token)
                        transport.handshake(url) { [weak self] result in
                            self?.locked {
                                guard let self, self.generation == token, self.running else { return }
                                do {
                                    let handshake = try BmobEventWire.handshake(result.get())
                                    let socketURL = try BmobEventWire.socketURL(domain, sid: handshake.sid)
                                    self.heartbeatTimeout = handshake.timeout + 7
                                    try transport.open(socketURL)
                                    self.armTimeout(30, token: token)
                                    self.receive(token)
                                } catch { self.failed(error, token: token) }
                            }
                        }
                    } catch { self.failed(error, token: token) }
                }
            } catch {
                self?.locked { self?.failed(error, token: token) }
            }
        }
    }

    private func cleanup() {
        generation = UUID() // Ignore callbacks from the previous connection, including cancel errors.
        configurationTask?.cancel()
        configurationTask = nil
        timeoutWork?.cancel()
        timeoutID = UUID()
        timeoutWork = nil
        reconnectWork?.cancel()
        reconnectWork = nil
        transport?.close()
        transport = nil
        connected = false
        ready = false
    }

    private func failed(_ error: Error, token: UUID) {
        guard running, generation == token else { return }
        cleanup()
        notify {
            $0.bmobEvent(self, didFailWithError: error)
            $0.bmobEventDidDisconnect(self, error: error)
        }
        guard reconnectEnabled else { running = false; return }
        let nextToken = generation
        let work = DispatchWorkItem { [weak self] in
            self?.locked {
                guard let self, self.running, self.reconnectEnabled, self.generation == nextToken else {
                    return
                }
                self.beginConnection()
            }
        }
        reconnectWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + reconnectDelay, execute: work)
    }

    private func armTimeout(_ interval: TimeInterval, token: UUID) {
        timeoutWork?.cancel()
        let id = UUID()
        timeoutID = id
        let work = DispatchWorkItem { [weak self] in
            self?.locked {
                guard let self, self.timeoutID == id else { return }
                self.failed(BmobError.timeout, token: token)
            }
        }
        timeoutWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + interval, execute: work)
    }

    private func receive(_ token: UUID) {
        transport?.receive { [weak self] result in
            self?.locked {
                guard let self, self.running, self.generation == token else { return }
                do {
                    try self.handle(result.get(), token: token)
                    if self.generation == token { self.receive(token) }
                } catch { self.failed(error, token: token) }
            }
        }
    }

    private func handle(_ text: String, token: UUID) throws {
        let parts = text.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[2].isEmpty else { throw BmobError.jsonParsingFailed }
        switch parts[0] {
        case "0":
            throw BmobError.operationNotAllowed(reason: "Realtime server disconnected")
        case "1":
            if !connected {
                connected = true
                armTimeout(heartbeatTimeout, token: token)
                notify { $0.bmobEventDidConnect(self) }
            }
        case "2":
            sendText("2::", token: token)
            armTimeout(heartbeatTimeout, token: token)
        case "5":
            guard parts.count == 4,
                  let data = String(parts[3]).data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String else { throw BmobError.jsonParsingFailed }
            if name == "client_send_data", connected, !ready {
                ready = true
                for subscription in subscriptions {
                    send(subscription, cancel: false)
                    guard generation == token else { return }
                }
                notify { $0.bmobEventCanStartListen(self) }
            } else if name == "server_pub", ready {
                guard let first = (json["args"] as? [Any])?.first else { throw BmobError.jsonParsingFailed }
                let payload: [String: Any]
                if let string = first as? String, let data = string.data(using: .utf8),
                   let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    payload = decoded
                } else if let dictionary = first as? [String: Any] { payload = dictionary }
                else { throw BmobError.jsonParsingFailed }
                let message = BmobEventMessage(json: payload)
                for continuation in streams.values { continuation.yield(message) }
                notify { $0.bmobEvent(self, didReceiveMessage: message) }
            }
        case "7":
            throw BmobError.operationNotAllowed(reason: parts.count == 4 ? String(parts[3]) : "Realtime server error")
        default: break // Ignore ACK/noop and other non-event packets.
        }
    }

    private func send(_ subscription: Subscription, cancel: Bool) {
        do {
            let text = try BmobEventWire.subscription(appKey: appKey, action: subscription.action,
                table: subscription.table, objectId: subscription.objectId, cancel: cancel)
            sendText(text, token: generation)
        } catch { failed(error, token: generation) }
    }

    private func sendText(_ text: String, token: UUID) {
        transport?.send(text) { [weak self] error in
            if let error { self?.locked { self?.failed(error, token: token) } }
        }
    }
}

public protocol BmobEventDelegate: AnyObject {
    func bmobEvent(_ event: BmobEvent, didReceiveMessage message: BmobEventMessage)
    func bmobEventDidConnect(_ event: BmobEvent)
    func bmobEventCanStartListen(_ event: BmobEvent)
    func bmobEventDidDisconnect(_ event: BmobEvent, error: Error?)
    func bmobEvent(_ event: BmobEvent, didFailWithError error: Error)
}

public extension BmobEventDelegate {
    func bmobEventDidConnect(_ event: BmobEvent) {}
    func bmobEventCanStartListen(_ event: BmobEvent) {}
    func bmobEventDidDisconnect(_ event: BmobEvent, error: Error?) {}
    func bmobEvent(_ event: BmobEvent, didFailWithError error: Error) {}
}

/// 实时事件消息。`rawValue` 保留服务端原始字段。
public struct BmobEventMessage: @unchecked Sendable {
    public let action: String?
    public let className: String?
    public let objectId: String?
    public let data: [String: Any]?
    public let rawValue: [String: Any]

    public init(json: [String: Any]) {
        rawValue = json
        action = json["action"] as? String
        className = json["tableName"] as? String ?? json["className"] as? String
        data = json["data"] as? [String: Any]
        // Table-wide notifications use an empty top-level objectId; the changed row is in data.
        let eventObjectId = json["objectId"] as? String
        objectId = eventObjectId.flatMap { $0.isEmpty ? nil : $0 } ?? data?["objectId"] as? String
    }
}

extension BmobManager {
    func eventConfiguration() throws -> (String, String) {
        guard isReady, !appKey.isEmpty else { throw BmobError.notInitialized }
        return (ioDomainOverride ?? ioDomain ?? "http://io.codenow.cn:3010", appKey)
    }
}

// Socket.IO 0.9 uses HTTP handshake + framed WebSocket messages, not Engine.IO.
enum BmobEventWire {
    static func baseURL(_ domain: String) throws -> URLComponents {
        let domain = domain.contains("://") ? domain : "http://" + domain
        guard var parts = URLComponents(string: domain), let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.path.isEmpty || parts.path == "/", parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true,
              let scheme = parts.scheme, ["http", "https", "ws", "wss"].contains(scheme) else {
            throw BmobError.invalidParameter(reason: "Invalid realtime domain")
        }
        parts.scheme = (scheme == "https" || scheme == "wss") ? "https" : "http"
        parts.path = "/socket.io/1/"
        parts.query = nil
        parts.fragment = nil
        return parts
    }

    static func handshakeURL(_ domain: String) throws -> URL {
        var parts = try baseURL(domain)
        parts.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970 * 1000)))]
        guard let url = parts.url else { throw BmobError.invalidParameter(reason: "Invalid realtime URL") }
        return url
    }

    static func handshake(_ text: String) throws -> (sid: String, timeout: TimeInterval) {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ":")
        guard parts.count == 4, !parts[0].isEmpty,
              parts[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
              let timeout = TimeInterval(parts[1]), timeout.isFinite, timeout > 0,
              let connectionTimeout = TimeInterval(parts[2]), connectionTimeout.isFinite, connectionTimeout > 0,
              parts[3].components(separatedBy: ",").contains("websocket") else {
            throw BmobError.operationNotAllowed(reason: "Invalid Socket.IO handshake or WebSocket unavailable")
        }
        return (parts[0], timeout)
    }

    static func socketURL(_ domain: String, sid: String) throws -> URL {
        var parts = try baseURL(domain)
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        parts.path += "websocket/" + sid
        guard let url = parts.url else { throw BmobError.invalidParameter(reason: "Invalid realtime URL") }
        return url
    }

    /// Use the request overload and supply the Origin sent by the legacy SDK.
    /// Socket.IO 0.9 can reject URLSession's default upgrade request with HTTP 403.
    static func socketRequest(_ url: URL) throws -> URLRequest {
        guard var origin = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = origin.scheme, ["ws", "wss"].contains(scheme),
              let host = origin.host, !host.isEmpty,
              origin.user == nil, origin.password == nil else {
            throw BmobError.invalidParameter(reason: "WebSocket URL must use ws or wss")
        }
        origin.scheme = scheme == "wss" ? "https" : "http"
        origin.path = ""
        origin.query = nil
        origin.fragment = nil
        guard let originURL = origin.url else {
            throw BmobError.invalidParameter(reason: "Invalid WebSocket Origin")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(originURL.absoluteString, forHTTPHeaderField: "Origin")
        return request
    }

    static func subscription(appKey: String, action: BmobActionType, table: String,
                             objectId: String, cancel: Bool) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: ["appKey": appKey,
            "tableName": table, "objectId": objectId, "action": (cancel ? "unsub_" : "") + action.rawValue])
        let envelope = try JSONSerialization.data(withJSONObject: ["name": cancel ? "client_unsub" : "client_sub",
            "args": [String(decoding: payload, as: UTF8.self)]])
        return "5:::" + String(decoding: envelope, as: UTF8.self)
    }
}

protocol BmobEventTransport: AnyObject {
    func handshake(_ url: URL, completion: @escaping (Result<String, Error>) -> Void)
    func open(_ url: URL) throws
    func receive(completion: @escaping (Result<String, Error>) -> Void)
    func send(_ text: String, completion: @escaping (Error?) -> Void)
    func close()
}

final class BmobEventURLSessionTransport: BmobEventTransport {
    private let session = URLSession(configuration: .ephemeral)
    private var handshakeTask: URLSessionDataTask?
    private var socket: URLSessionWebSocketTask?

    func handshake(_ url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        handshakeTask = session.dataTask(with: url) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let data, let text = String(data: data, encoding: .utf8) else {
                completion(.failure(BmobError.operationNotAllowed(reason: "Realtime handshake failed")))
                return
            }
            completion(.success(text))
        }
        handshakeTask?.resume()
    }
    func open(_ url: URL) throws {
        let request = try BmobEventWire.socketRequest(url)
        socket = session.webSocketTask(with: request)
        socket?.resume()
    }
    func receive(completion: @escaping (Result<String, Error>) -> Void) {
        socket?.receive { result in
            completion(result.flatMap { message in
                switch message {
                case .string(let text): return .success(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { return .success(text) }
                    return .failure(BmobError.jsonParsingFailed)
                @unknown default: return .failure(BmobError.jsonParsingFailed)
                }
            })
        }
    }
    func send(_ text: String, completion: @escaping (Error?) -> Void) {
        socket?.send(.string(text), completionHandler: completion)
    }
    func close() {
        handshakeTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}

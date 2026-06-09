import Foundation

// MARK: - BmobEvent

/// Bmob 实时数据监听（WebSocket 长连接）
///
/// ```swift
/// let event = BmobEvent()
/// event.delegate = self
/// event.connect()
/// event.listenTableChange(className: "Note")
/// ```
public class BmobEvent {

    // MARK: - Properties

    /// 事件代理
    public weak var delegate: BmobEventDelegate?

    /// 是否已连接
    public private(set) var isConnected: Bool = false

    /// 是否自动重连
    public var autoReconnect: Bool = true

    /// WebSocket 任务
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var reconnectTimer: Timer?

    /// 监听表名集合
    private var listenedTables: Set<String> = []
    private var listenedRows: [String: Set<String>] = [:]

    /// 心跳定时器
    private var pingTimer: Timer?

    public init() {}

    // MARK: - Connection

    /// 连接 WebSocket
    public func connect() {
        guard let ioDomain = ioDomain() else {
            delegate?.bmobEvent(self, didFailWithError: BmobError.notInitialized)
            return
        }

        let url = URL(string: ioDomain)!
        session = URLSession(configuration: .default)
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()

        isConnected = true
        delegate?.bmobEventDidConnect(self)

        startHeartbeat()
        receiveMessage()

        // 重新订阅已监听的表/行
        for table in listenedTables {
            sendListenTable(table)
        }
        for (table, rows) in listenedRows {
            for rowId in rows {
                sendListenRow(table, objectId: rowId)
            }
        }
    }

    /// 断开连接
    public func disconnect() {
        stopHeartbeat()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session = nil
        isConnected = false
        reconnectTimer?.invalidate()
        delegate?.bmobEventDidDisconnect(self, error: nil)
    }

    // MARK: - Table Listen

    /// 监听表级别变更
    public func listenTableChange(className: String) {
        listenedTables.insert(className)
        guard isConnected else { return }
        sendListenTable(className)
    }

    /// 取消表监听
    public func cancelListenTableChange(className: String) {
        listenedTables.remove(className)
    }

    // MARK: - Row Listen

    /// 监听行级别变更
    public func listenRowChange(className: String, objectId: String) {
        if listenedRows[className] == nil {
            listenedRows[className] = []
        }
        listenedRows[className]?.insert(objectId)
        guard isConnected else { return }
        sendListenRow(className, objectId: objectId)
    }

    /// 取消行监听
    public func cancelListenRowChange(className: String, objectId: String) {
        listenedRows[className]?.remove(objectId)
    }

    // MARK: - AsyncStream

    /// 事件流（AsyncStream）
    public func eventStream() -> AsyncStream<BmobEventMessage> {
        AsyncStream { continuation in
            // 通过内部代理桥接到 AsyncStream
            let bridge = BmobEventStreamBridge(continuation: continuation)
            self.delegate = bridge
        }
    }

    // MARK: - Private

    private func ioDomain() -> String? {
        // 从 UserDefaults 读取 init 时保存的 io 域名
        return UserDefaults.standard.string(forKey: "BmobIODomain")
    }

    private func sendListenTable(_ className: String) {
        let message: [String: Any] = [
            "action": "listen",
            "className": className
        ]
        send(message: message)
    }

    private func sendListenRow(_ className: String, objectId: String) {
        let message: [String: Any] = [
            "action": "listenRow",
            "className": className,
            "objectId": objectId
        ]
        send(message: message)
    }

    private func send(message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { _ in }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let event = BmobEventMessage(json: json)
                        self.delegate?.bmobEvent(self, didReceiveMessage: event)
                    }
                case .data(let data):
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let event = BmobEventMessage(json: json)
                        self.delegate?.bmobEvent(self, didReceiveMessage: event)
                    }
                @unknown default:
                    break
                }
                // 继续接收下一条消息
                self.receiveMessage()

            case .failure(let error):
                self.isConnected = false
                self.delegate?.bmobEventDidDisconnect(self, error: error)
                if self.autoReconnect {
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func startHeartbeat() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.webSocketTask?.sendPing { _ in }
        }
    }

    private func stopHeartbeat() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
}

// MARK: - BmobEventDelegate

/// BmobEvent 代理协议
public protocol BmobEventDelegate: AnyObject {
    func bmobEvent(_ event: BmobEvent, didReceiveMessage message: BmobEventMessage)
    func bmobEventDidConnect(_ event: BmobEvent)
    func bmobEventDidDisconnect(_ event: BmobEvent, error: Error?)
    func bmobEvent(_ event: BmobEvent, didFailWithError error: Error)
}

// Default empty implementations
public extension BmobEventDelegate {
    func bmobEventDidConnect(_ event: BmobEvent) {}
    func bmobEventDidDisconnect(_ event: BmobEvent, error: Error?) {}
    func bmobEvent(_ event: BmobEvent, didFailWithError error: Error) {}
}

// MARK: - BmobEventMessage

/// 实时事件消息
public struct BmobEventMessage: Sendable {
    public let action: String?
    public let className: String?
    public let objectId: String?
    public let data: [String: Any]?

    public init(json: [String: Any]) {
        self.action = json["action"] as? String
        self.className = json["className"] as? String
        self.objectId = json["objectId"] as? String
        self.data = json["data"] as? [String: Any]
    }
}

// MARK: - BmobEventStreamBridge

/// AsyncStream 桥接器
private final class BmobEventStreamBridge: BmobEventDelegate {
    let continuation: AsyncStream<BmobEventMessage>.Continuation

    init(continuation: AsyncStream<BmobEventMessage>.Continuation) {
        self.continuation = continuation
    }

    func bmobEvent(_ event: BmobEvent, didReceiveMessage message: BmobEventMessage) {
        continuation.yield(message)
    }

    func bmobEventDidConnect(_ event: BmobEvent) {}
    func bmobEventDidDisconnect(_ event: BmobEvent, error: Error?) {
        if let _ = error {
            continuation.finish()
        }
    }
    func bmobEvent(_ event: BmobEvent, didFailWithError error: Error) {
        continuation.finish()
    }
}

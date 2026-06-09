import Foundation
import BmobCore

// MARK: - BmobObject

/// Bmob 数据对象基类
/// 内部使用字典存储所有字段值，支持运行时动态属性访问
///
/// ```swift
/// let note = BmobObject(className: "Note")
/// note["title"] = "Hello"
/// note["count"] = 42
/// try await note.save()
/// ```
open class BmobObject: @unchecked Sendable {

    // MARK: - Properties

    /// 表名
    public let className: String

    /// 对象 ID（保存后由服务器分配）
    public internal(set) var objectId: String?

    /// 创建时间
    public internal(set) var createdAt: Date?

    /// 更新时间
    public internal(set) var updatedAt: Date?

    /// 内部数据字典
    private var _data: [String: Any]

    // MARK: - Initialization

    /// 通过表名创建
    /// - Parameter className: Bmob 表名
    public init(className: String) {
        self.className = className
        self._data = [:]
    }

    /// 通过表名和数据字典创建
    /// - Parameters:
    ///   - className: 表名
    ///   - data: 初始数据字典
    required public init(className: String, data: [String: Any]) {
        self.className = className
        self._data = [:]
        // 解析系统字段
        if let id = data["objectId"] as? String {
            self.objectId = id
        }
        if let createdAtStr = data["createdAt"] as? String {
            self.createdAt = BmobDateFormatter.date(from: createdAtStr)
        }
        if let updatedAtStr = data["updatedAt"] as? String {
            self.updatedAt = BmobDateFormatter.date(from: updatedAtStr)
        }
        // 复制用户字段（排除系统字段和类型标记）
        for (key, value) in data {
            if key == "objectId" || key == "createdAt" || key == "updatedAt" {
                continue
            }
            _data[key] = value
        }
    }

    // MARK: - Key-Value Access

    /// 下标访问（动态属性）
    public subscript(key: String) -> Any? {
        get { _data[key] }
        set { _data[key] = newValue }
    }

    /// 获取所有用户字段
    public var data: [String: Any] {
        _data
    }

    /// 获取完整数据（含系统字段）
    public var fullData: [String: Any] {
        var dict = _data
        if let objectId = objectId { dict["objectId"] = objectId }
        if let createdAt = createdAt { dict["createdAt"] = BmobDateFormatter.string(from: createdAt) }
        if let updatedAt = updatedAt { dict["updatedAt"] = BmobDateFormatter.string(from: updatedAt) }
        return dict
    }

    // MARK: - CRUD Operations

    /// 保存对象（新建）
    /// - Returns: 保存后的对象（含 objectId）
    @discardableResult
    open func save() async throws -> BmobObject {
        let manager = BmobManager.shared
        let domain = await manager.apiDomain
        guard let url = URL(string: "\(domain)/8/create") else {
            throw BmobError.notInitialized
        }

        try await waitForInitialization()

        let serialized = try BmobSerializer.serialize(_data)
        let parameters: [String: Any] = [
            "c": className,
            "data": serialized
        ]

        let response = try await BmobHTTPClient.post(url: url, parameters: parameters)

        guard let responseData = response["data"] as? [String: Any] else {
            throw BmobError.serverError(code: -1, message: "Invalid save response")
        }

        // 更新本地数据
        if let id = responseData["objectId"] as? String {
            self.objectId = id
            _data["objectId"] = id
        }
        if let createdAtStr = responseData["createdAt"] as? String {
            self.createdAt = BmobDateFormatter.date(from: createdAtStr)
        }
        return self
    }

    /// 更新对象
    /// - Returns: 更新后的对象
    @discardableResult
    open func update() async throws -> BmobObject {
        guard let objectId = objectId else {
            throw BmobError.invalidParameter(reason: "objectId is required for update")
        }
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/update") else {
            throw BmobError.notInitialized
        }

        try await waitForInitialization()

        // 过滤保留字段，避免发送 objectId/createdAt/updatedAt 到服务端
        let reservedKeys: Set<String> = ["objectId", "createdAt", "updatedAt"]
        var updateData = _data
        for key in reservedKeys {
            updateData.removeValue(forKey: key)
        }
        let serialized = try BmobSerializer.serialize(updateData)
        let parameters: [String: Any] = [
            "c": className,
            "objectId": objectId,
            "data": serialized
        ]

        let response = try await BmobHTTPClient.post(url: url, parameters: parameters)

        if let responseData = response["data"] as? [String: Any],
           let updatedAtStr = responseData["updatedAt"] as? String {
            self.updatedAt = BmobDateFormatter.date(from: updatedAtStr)
        }

        return self
    }

    /// 删除对象
    open func delete() async throws {
        guard let objectId = objectId else {
            throw BmobError.invalidParameter(reason: "objectId is required for delete")
        }
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/delete") else {
            throw BmobError.notInitialized
        }

        try await waitForInitialization()

        let parameters: [String: Any] = [
            "c": className,
            "objectId": objectId
        ]

        _ = try await BmobHTTPClient.post(url: url, parameters: parameters)

        // 清除本地数据
        self.objectId = nil
        self._data.removeAll()
    }

    /// 原子计数器：递增指定字段
    /// - Parameters:
    ///   - key: 字段名
    ///   - amount: 递增量（默认 1）
    open func incrementKey(_ key: String, by amount: Int = 1) {
        _data[key] = BmobIncrement(amount: amount)
    }

    /// 原子计数器：递减指定字段
    /// - Parameters:
    ///   - key: 字段名
    ///   - amount: 递减量（默认 1）
    open func decrementKey(_ key: String, by amount: Int = 1) {
        _data[key] = BmobIncrement(amount: -amount)
    }

    /// 清空本地修改
    open func revert() {
        _data.removeAll()
    }

    // MARK: - Subclass Helpers

    /// 设置系统字段（仅供子类使用）
    open func setSystemFields(objectId: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
        if let id = objectId { self.objectId = id }
        if let ca = createdAt { self.createdAt = ca }
        if let ua = updatedAt { self.updatedAt = ua }
    }

    // MARK: - Private

    private func waitForInitialization() async throws {
        try await BmobManager.shared.waitUntilReady()
    }
}

// MARK: - BmobPointer

/// 指向另一个 BmobObject 的指针
public struct BmobPointer: Sendable {
    public let className: String
    public let objectId: String

    public init(className: String, objectId: String) {
        self.className = className
        self.objectId = objectId
    }

    public init(object: BmobObject) {
        self.className = object.className
        self.objectId = object.objectId ?? ""
    }

    /// 序列化为 Dictionary
    var dictionary: [String: Any] {
        [
            "__type": "Pointer",
            "className": className,
            "objectId": objectId
        ]
    }
}

// MARK: - BmobIncrement

/// 原子计数器操作
struct BmobIncrement: Sendable {
    let amount: Int

    var dictionary: [String: Any] {
        ["__op": "Increment", "amount": amount]
    }
}

// MARK: - BmobDateFormatter

/// 日期格式化工具（Bmob 使用 "yyyy-MM-dd HH:mm:ss" 格式）
public enum BmobDateFormatter {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    public static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    public static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}

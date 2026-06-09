import Foundation
import BmobCore

// MARK: - BmobBatchOperation

/// 批量操作类型
public enum BmobBatchOperation: Sendable {
    case create(object: BmobObject)
    case update(object: BmobObject)
    case delete(className: String, objectId: String)
}

// MARK: - BmobBatch

/// Bmob 批量操作
/// 单次最多 50 条
///
/// ```swift
/// let batch = BmobBatch()
/// batch.create(object1)
/// batch.update(object2)
/// try await batch.execute()
/// ```
public class BmobBatch {

    /// 单个批次操作上限
    public static let maxBatchSize = 50

    private var operations: [BmobBatchOperation] = []

    /// 添加创建操作
    public func create(_ object: BmobObject) {
        operations.append(.create(object: object))
    }

    /// 添加更新操作
    public func update(_ object: BmobObject) {
        operations.append(.update(object: object))
    }

    /// 添加删除操作
    public func delete(className: String, objectId: String) {
        operations.append(.delete(className: className, objectId: objectId))
    }

    /// 添加删除操作（从对象获取）
    public func delete(_ object: BmobObject) {
        guard let objectId = object.objectId else { return }
        operations.append(.delete(className: object.className, objectId: objectId))
    }

    /// 当前操作数
    public var count: Int {
        operations.count
    }

    /// 是否为空
    public var isEmpty: Bool {
        operations.isEmpty
    }

    /// 执行批量操作
    /// - Returns: 批量操作结果数组（顺序与添加顺序一致）
    @discardableResult
    public func execute() async throws -> [BmobBatchResult] {
        guard !operations.isEmpty else {
            throw BmobError.invalidParameter(reason: "Batch is empty")
        }
        guard operations.count <= BmobBatch.maxBatchSize else {
            throw BmobError.invalidParameter(reason: "Batch exceeds max size \(BmobBatch.maxBatchSize)")
        }

        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/batch") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        var requests: [[String: Any]] = []
        for op in operations {
            var request: [String: Any] = [:]

            switch op {
            case .create(let object):
                request["method"] = "create"
                request["c"] = object.className
                request["data"] = try BmobSerializer.serialize(object.data)
            case .update(let object):
                guard let objectId = object.objectId else {
                    continue
                }
                // 过滤保留字段
                var updateData = object.data
                for key in ["objectId", "createdAt", "updatedAt"] {
                    updateData.removeValue(forKey: key)
                }
                request["method"] = "update"
                request["c"] = object.className
                request["objectId"] = objectId
                request["data"] = try BmobSerializer.serialize(updateData)
            case .delete(let className, let objectId):
                request["method"] = "delete"
                request["c"] = className
                request["objectId"] = objectId
            }

            requests.append(request)
        }

        let parameters: [String: Any] = ["requests": requests]

        let response = try await BmobHTTPClient.post(url: url, parameters: parameters)

        var results: [BmobBatchResult] = []
        // 支持多种响应格式
        let responseResults: [[String: Any]]?
        if let r = response["results"] as? [[String: Any]] {
            responseResults = r
        } else if let r = response["data"] as? [[String: Any]] {
            responseResults = r
        } else {
            responseResults = nil
        }
        if let responseResults = responseResults {
            for result in responseResults {
                if let success = result["success"] as? [String: Any] {
                    results.append(.success(data: success))
                } else if let error = result["error"] as? [String: Any] {
                    let code = error["code"] as? Int ?? -1
                    let message = error["error"] as? String ?? "Batch error"
                    results.append(.failure(code: code, message: message))
                }
            }
        }

        // 更新创建的对象的 objectId
        for (index, op) in operations.enumerated() {
            guard index < results.count else { break }
            if case .create(let object) = op,
               case .success(let data) = results[index],
               let objectId = data["objectId"] as? String {
                object.objectId = objectId
                if let createdAtStr = data["createdAt"] as? String {
                    object.createdAt = BmobDateFormatter.date(from: createdAtStr)
                }
            }
        }

        operations.removeAll()
        return results
    }
}

// MARK: - BmobBatchResult

/// 批量操作单条结果
public enum BmobBatchResult: Sendable {
    case success(data: [String: Any])
    case failure(code: Int, message: String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    public var errorMessage: String? {
        if case .failure(_, let message) = self { return message }
        return nil
    }
}

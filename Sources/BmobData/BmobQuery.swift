import Foundation
#if canImport(BmobCore)
@_exported import BmobCore
#endif

// MARK: - BmobQuery

/// Bmob 查询构建器
///
/// ```swift
/// let query = BmobQuery(className: "Note")
///     .whereKey("status", .equalTo(1))
///     .order(byDescending: "createdAt")
///     .limit(20)
/// let results = try await query.find()
/// ```
public class BmobQuery {

    // MARK: - Properties

    /// 表名
    public let className: String

    /// 查询条件
    private var conditions: [String: Any] = [:]

    /// 限制返回条数
    public var limit: Int = 100

    /// 跳过条数
    public var skip: Int = 0

    /// 排序字段（"field" → 1 asc / -1 desc）
    private var orderFields: [String: Int] = [:]

    /// 指定返回列
    private var selectedKeys: [String]?

    /// 关联查询字段
    private var includeKeys: [String]?

    /// 统计查询配置
    private var statisticsConfig: StatisticsConfig?

    /// 缓存策略
    public var cachePolicy: BmobCachePolicy = .networkOnly

    // MARK: - Initialization

    public init(className: String) {
        self.className = className
    }

    // MARK: - Condition Operators

    /// 条件操作符
    public enum Operator: String {
        case equalTo = ""
        case notEqualTo = "$ne"
        case lessThan = "$lt"
        case lessThanOrEqualTo = "$lte"
        case greaterThan = "$gt"
        case greaterThanOrEqualTo = "$gte"
        case containedIn = "$in"
        case notContainedIn = "$nin"
        case exists = "$exists"
        case regex = "$regex"
        case nearGeoPoint = "$nearSphere"
        case withinGeoBox = "$within"
    }

    /// 添加等于条件
    @discardableResult
    public func whereKey(_ key: String, equalTo value: Any) -> BmobQuery {
        conditions[key] = try? BmobSerializer.serializeValue(value)
        return self
    }

    /// 添加不等于条件
    @discardableResult
    public func whereKey(_ key: String, notEqualTo value: Any) -> BmobQuery {
        conditions[key] = [
            Operator.notEqualTo.rawValue: (try? BmobSerializer.serializeValue(value)) ?? value
        ]
        return self
    }

    /// 添加小于条件
    @discardableResult
    public func whereKey(_ key: String, lessThan value: Any) -> BmobQuery {
        conditions[key] = [
            Operator.lessThan.rawValue: (try? BmobSerializer.serializeValue(value)) ?? value
        ]
        return self
    }

    /// 添加小于等于条件
    @discardableResult
    public func whereKey(_ key: String, lessThanOrEqualTo value: Any) -> BmobQuery {
        conditions[key] = [
            Operator.lessThanOrEqualTo.rawValue: (try? BmobSerializer.serializeValue(value)) ?? value
        ]
        return self
    }

    /// 添加大于条件
    @discardableResult
    public func whereKey(_ key: String, greaterThan value: Any) -> BmobQuery {
        conditions[key] = [
            Operator.greaterThan.rawValue: (try? BmobSerializer.serializeValue(value)) ?? value
        ]
        return self
    }

    /// 添加大于等于条件
    @discardableResult
    public func whereKey(_ key: String, greaterThanOrEqualTo value: Any) -> BmobQuery {
        conditions[key] = [
            Operator.greaterThanOrEqualTo.rawValue: (try? BmobSerializer.serializeValue(value)) ?? value
        ]
        return self
    }

    /// 包含于数组
    @discardableResult
    public func whereKey(_ key: String, containedIn values: [Any]) -> BmobQuery {
        conditions[key] = [
            Operator.containedIn.rawValue: values
        ]
        return self
    }

    /// 不包含于数组
    @discardableResult
    public func whereKey(_ key: String, notContainedIn values: [Any]) -> BmobQuery {
        conditions[key] = [
            Operator.notContainedIn.rawValue: values
        ]
        return self
    }

    /// 字段存在
    @discardableResult
    public func whereKeyExists(_ key: String) -> BmobQuery {
        conditions[key] = [
            Operator.exists.rawValue: true
        ]
        return self
    }

    /// 字段不存在
    @discardableResult
    public func whereKeyDoesNotExist(_ key: String) -> BmobQuery {
        conditions[key] = [
            Operator.exists.rawValue: false
        ]
        return self
    }

    /// 正则匹配
    @discardableResult
    public func whereKey(_ key: String, matchesRegex regex: String) -> BmobQuery {
        conditions[key] = [
            Operator.regex.rawValue: regex
        ]
        return self
    }

    /// 前缀匹配
    @discardableResult
    public func whereKey(_ key: String, startsWith prefix: String) -> BmobQuery {
        conditions[key] = [
            Operator.regex.rawValue: "^\(NSRegularExpression.escapedPattern(for: prefix))"
        ]
        return self
    }

    /// 后缀匹配
    @discardableResult
    public func whereKey(_ key: String, endsWith suffix: String) -> BmobQuery {
        conditions[key] = [
            Operator.regex.rawValue: "\(NSRegularExpression.escapedPattern(for: suffix))$"
        ]
        return self
    }

    // MARK: - Compound Queries

    /// AND 组合查询
    public static func and(_ queries: [BmobQuery]) -> BmobQuery? {
        return compoundQuery(queries, key: "$and")
    }

    /// OR 组合查询
    public static func or(_ queries: [BmobQuery]) -> BmobQuery? {
        return compoundQuery(queries, key: "$or")
    }

    private static func compoundQuery(_ queries: [BmobQuery], key: String) -> BmobQuery? {
        guard !queries.isEmpty, let first = queries.first else { return nil }
        let compound = BmobQuery(className: first.className)
        let conditionArray = queries.compactMap { q -> [String: Any]? in
            if q.conditions.isEmpty { return nil }
            return q.conditions
        }
        compound.conditions = [key: conditionArray]
        return compound
    }

    // MARK: - Sorting

    /// 升序排列
    @discardableResult
    public func order(byAscending key: String) -> BmobQuery {
        orderFields[key] = 1
        return self
    }

    /// 降序排列
    @discardableResult
    public func order(byDescending key: String) -> BmobQuery {
        orderFields[key] = -1
        return self
    }

    /// 添加升序排列
    @discardableResult
    public func addAscendingOrder(_ key: String) -> BmobQuery {
        return order(byAscending: key)
    }

    /// 添加降序排列
    @discardableResult
    public func addDescendingOrder(_ key: String) -> BmobQuery {
        return order(byDescending: key)
    }

    // MARK: - Selection

    /// 指定返回列
    @discardableResult
    public func selectKeys(_ keys: [String]) -> BmobQuery {
        selectedKeys = keys
        return self
    }

    /// 关联查询（支持嵌套点号路径，如 "author.company"）
    @discardableResult
    public func includeKey(_ key: String) -> BmobQuery {
        if includeKeys == nil {
            includeKeys = []
        }
        includeKeys?.append(key)
        return self
    }

    // MARK: - Pagination

    /// 设置分页限制
    @discardableResult
    public func limit(_ count: Int) -> BmobQuery {
        self.limit = count
        return self
    }

    /// 设置跳过条数
    @discardableResult
    public func skip(_ count: Int) -> BmobQuery {
        self.skip = count
        return self
    }

    // MARK: - Statistics

    /// 统计查询配置
    struct StatisticsConfig {
        var groupBy: [String]?
        var having: [String: Any]?
    }

    /// 统计查询（sum/max/min/average）
    /// 使用前请配合 selectKeys 指定操作列
    @discardableResult
    public func statistics() -> BmobQuery {
        statisticsConfig = StatisticsConfig()
        return self
    }

    /// 分组统计
    @discardableResult
    public func groupBy(_ keys: [String]) -> BmobQuery {
        if statisticsConfig == nil { statisticsConfig = StatisticsConfig() }
        statisticsConfig?.groupBy = keys
        return self
    }

    /// Having 过滤
    @discardableResult
    public func having(_ conditions: [String: Any]) -> BmobQuery {
        if statisticsConfig == nil { statisticsConfig = StatisticsConfig() }
        statisticsConfig?.having = conditions
        return self
    }

    // MARK: - Geo Queries

    /// 地理位置近点查询
    @discardableResult
    public func whereKey(_ key: String, nearGeoPoint point: BmobGeoPoint) -> BmobQuery {
        conditions[key] = [
            Operator.nearGeoPoint.rawValue: point.dictionary
        ]
        return self
    }

    /// 公里范围内
    @discardableResult
    public func whereKey(_ key: String, nearGeoPoint point: BmobGeoPoint, withinKilometers km: Double) -> BmobQuery {
        conditions[key] = [
            Operator.nearGeoPoint.rawValue: point.dictionary,
            "$maxDistanceInKilometers": km
        ]
        return self
    }

    /// 英里范围内
    @discardableResult
    public func whereKey(_ key: String, nearGeoPoint point: BmobGeoPoint, withinMiles miles: Double) -> BmobQuery {
        conditions[key] = [
            Operator.nearGeoPoint.rawValue: point.dictionary,
            "$maxDistanceInMiles": miles
        ]
        return self
    }

    /// 弧度范围内
    @discardableResult
    public func whereKey(_ key: String, nearGeoPoint point: BmobGeoPoint, withinRadians radians: Double) -> BmobQuery {
        conditions[key] = [
            Operator.nearGeoPoint.rawValue: point.dictionary,
            "$maxDistanceInRadians": radians
        ]
        return self
    }

    /// 矩形区域内
    @discardableResult
    public func whereKey(_ key: String, withinGeoBox southwest: BmobGeoPoint, northeast: BmobGeoPoint) -> BmobQuery {
        conditions[key] = [
            Operator.withinGeoBox.rawValue: [
                southwest.dictionary,
                northeast.dictionary
            ]
        ]
        return self
    }

    // MARK: - Count

    /// 查询计数
    public func count() async throws -> Int {
        var params = buildRequestParams()
        params["count"] = 1
        params["limit"] = 0

        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/find") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()
        print("🔍 [BmobQuery.count] 请求参数 keys: \(params.keys.sorted())")
        let response = try await BmobHTTPClient.post(url: url, parameters: params)
        print("🔍 [BmobQuery.count] 响应 keys: \(response.keys.sorted())")
        print("🔍 [BmobQuery.count] 完整响应: \(response)")

        // 格式1: {"count": N}
        if let count = response["count"] as? Int {
            return count
        }
        // 格式2: {"data": {"count": N}}
        if let data = response["data"] as? [String: Any],
           let count = data["count"] as? Int {
            return count
        }
        // 格式3: {"data": [...]} → 用数组长度
        if let dataArray = response["data"] as? [[String: Any]] {
            print("🔍 [BmobQuery.count] data 是数组，长度: \(dataArray.count)")
            return dataArray.count
        }
        // 格式4: data 对象中可能包含 results 数组
        if let dataDict = response["data"] as? [String: Any],
           let results = dataDict["results"] as? [[String: Any]] {
            print("🔍 [BmobQuery.count] data.results 长度: \(results.count)")
            return results.count
        }
        return 0
    }

    // MARK: - Execute

    /// 查询单条记录
    public func get(objectId: String) async throws -> BmobObject? {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/find") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let parameters: [String: Any] = [
            "c": className,
            "objectId": objectId,
            "data": NSNull()
        ]

        let response: [String: Any]
        do {
            response = try await BmobHTTPClient.post(url: url, parameters: parameters)
        } catch let error as BmobError {
            // code 101 = object not found，返回 nil 而非抛错
            if error.code == 101 {
                return nil
            }
            throw error
        }

        guard let data = response["data"] as? [String: Any],
              data["objectId"] != nil else {
            return nil
        }

        let deserialized = BmobSerializer.deserialize(data)
        return BmobObject(className: className, data: deserialized)
    }

    /// 执行查询
    public func find() async throws -> [BmobObject] {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/find") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let parameters = buildRequestParams()
        print("🔍 [BmobQuery.find] 请求参数: c=\(parameters["c"] ?? "nil"), limit=\(parameters["limit"] ?? "nil"), skip=\(parameters["skip"] ?? "nil"), data_in_params=\(parameters["data"] != nil ? "YES" : "NO")")
        if let data = parameters["data"] {
            print("🔍 [BmobQuery.find] data 内容: \(data)")
        }
        if let order = parameters["order"] {
            print("🔍 [BmobQuery.find] order 内容: \(order)")
        }
        if let keys = parameters["keys"] {
            print("🔍 [BmobQuery.find] keys 内容: \(keys)")
        }
        let response = try await BmobHTTPClient.post(url: url, parameters: parameters)
        print("🔍 [BmobQuery.find] 响应 keys: \(response.keys.sorted())")
        if let dataValue = response["data"] {
            print("🔍 [BmobQuery.find] response[data] 类型: \(type(of: dataValue)), 值: \(dataValue)")
        }

        // 尝试多种响应格式
        // 格式1: {"results": [...]}
        if let results = response["results"] as? [[String: Any]] {
            return results.map { dict in
                let deserialized = BmobSerializer.deserialize(dict)
                return BmobObject(className: className, data: deserialized)
            }
        }

        // 格式2: {"data": [...]}
        if let data = response["data"] as? [[String: Any]] {
            return data.map { dict in
                let deserialized = BmobSerializer.deserialize(dict)
                return BmobObject(className: className, data: deserialized)
            }
        }

        // 格式3: {"data": {"results": [...]}}
        if let dataDict = response["data"] as? [String: Any],
           let results = dataDict["results"] as? [[String: Any]] {
            return results.map { dict in
                let deserialized = BmobSerializer.deserialize(dict)
                return BmobObject(className: className, data: deserialized)
            }
        }

        // 调试：打印响应键以便排查格式问题
        print("⚠️ [BmobQuery.find] 未识别的响应格式，keys: \(response.keys.sorted())")
        if let dataValue = response["data"] {
            print("⚠️ [BmobQuery.find] response[\"data\"] type: \(type(of: dataValue))")
        }

        return []
    }

    /// 统计查询（sum/max/min/average）
    public func statistics() async throws -> [[String: Any]] {
        statisticsConfig = (statisticsConfig ?? StatisticsConfig())
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/cloud_query") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let parameters = buildRequestParams()
        let response = try await BmobHTTPClient.post(url: url, parameters: parameters)

        if let results = response["results"] as? [[String: Any]] {
            return results
        }
        return []
    }

    /// BQL 查询
    public static func query(bql: String, parameters: [Any]? = nil) async throws -> [BmobObject] {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/cloud_query") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        var params: [String: Any] = ["bql": bql]
        if let parameters = parameters {
            params["values"] = parameters
        }

        let response = try await BmobHTTPClient.post(url: url, parameters: params)

        // 支持多种响应格式
        if let results = response["results"] as? [[String: Any]] {
            return results.map { dict in
                let deserialized = BmobSerializer.deserialize(dict)
                return BmobObject(className: "Unknown", data: deserialized)
            }
        }
        if let data = response["data"] as? [[String: Any]] {
            return data.map { dict in
                let deserialized = BmobSerializer.deserialize(dict)
                return BmobObject(className: "Unknown", data: deserialized)
            }
        }
        if let dataDict = response["data"] as? [String: Any],
           let results = dataDict["results"] as? [[String: Any]] {
            return results.map { dict in
                let deserialized = BmobSerializer.deserialize(dict)
                return BmobObject(className: "Unknown", data: deserialized)
            }
        }
        return []
    }

    /// BQL 统计查询
    public static func statistics(bql: String, parameters: [Any]? = nil) async throws -> [[String: Any]] {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/cloud_query") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        var params: [String: Any] = ["bql": bql]
        if let parameters = parameters {
            params["values"] = parameters
        }

        let response = try await BmobHTTPClient.post(url: url, parameters: params)

        if let results = response["results"] as? [[String: Any]] {
            return results
        }
        if let data = response["data"] as? [[String: Any]] {
            return data
        }
        if let dataDict = response["data"] as? [String: Any],
           let results = dataDict["results"] as? [[String: Any]] {
            return results
        }
        return []
    }

    // MARK: - Private

    /// 构建请求参数字典
    /// 参考旧版 ObjC SDK BmobQuery.m 中 makeQueryCondiction + requestDictionaryWithClassname:data:
    /// 格式: {"c": className, "data": {"where": ..., "limit": ..., "skip": ..., "order": ..., "keys": ..., "include": ...}, "client": ..., "v": ..., "appSign": ..., "timestamp": ...}
    private func buildRequestParams() -> [String: Any] {
        var dataDict: [String: Any] = [:]

        // 查询条件
        if !conditions.isEmpty {
            dataDict["where"] = conditions
        }

        // limit (旧版: limit != 0 才设置)
        if limit != 0 {
            dataDict["limit"] = limit
        }

        // skip (旧版: skip != 0 才设置)
        if skip != 0 {
            dataDict["skip"] = skip
        }

        // 排序 (旧版: order 放在 data 内部)
        if !orderFields.isEmpty {
            let orderStr = orderFields.map { "\($0.key) \($0.value == 1 ? "asc" : "desc")" }.joined(separator: ",")
            dataDict["order"] = orderStr
        }

        // 指定列
        if let keys = selectedKeys {
            dataDict["keys"] = keys.joined(separator: ",")
        }

        // 关联查询
        if let include = includeKeys {
            dataDict["include"] = include.joined(separator: ",")
        }

        // 统计
        if let stats = statisticsConfig {
            if let groupBy = stats.groupBy {
                dataDict["groupby"] = groupBy.joined(separator: ",")
            }
            if let having = stats.having {
                dataDict["having"] = having
            }
        }

        // 顶层参数: c + data (data 为空字典时用 NSNull)
        var params: [String: Any] = [
            "c": className
        ]

        if dataDict.isEmpty {
            params["data"] = NSNull()
        } else {
            params["data"] = dataDict
        }

        return params
    }
}

// MARK: - BmobCachePolicy

/// 查询缓存策略
public enum BmobCachePolicy: Sendable {
    /// 忽略缓存，仅网络
    case networkOnly
    /// 仅从缓存读取
    case cacheOnly
    /// 缓存优先，失败时网络
    case cacheElseNetwork
    /// 网络优先，失败时缓存
    case networkElseCache
    /// 先取缓存再查网络（两次回调）
    case cacheThenNetwork
}

import Foundation
#if canImport(BmobCore)
@_exported import BmobCore
#endif

// MARK: - BmobCloud

/// Bmob 云函数调用
///
/// ```swift
/// // 无参数调用
/// let result = try await BmobCloud.run(function: "hello")
///
/// // 带参数调用
/// let result = try await BmobCloud.run(function: "greet", params: ["name": "World"])
///
/// // 类型安全解码
/// struct Greeting: Decodable {
///     let message: String
/// }
/// let greeting: Greeting = try await BmobCloud.run(function: "greet", params: ["name": "World"])
/// ```
public enum BmobCloud {

    /// 调用云函数
    /// - Parameters:
    ///   - function: 云函数名称
    ///   - params: 参数（可选）
    /// - Returns: 任意类型结果
    @discardableResult
    public static func run(function: String, params: [String: Any]? = nil) async throws -> Any {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/functions") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        // 参考旧版 ObjC SDK: BmobCloud.m
        // 云函数名放在 data._e，参数直接混入 data
        // 最终加密前格式: {"data": {"_e": "funcName", "param1": "val1", ...}, "client": ..., "v": ...}
        var dataDict: [String: Any] = ["_e": function]
        if let params = params {
            for (key, value) in params {
                dataDict[key] = value
            }
        }

        let requestParams: [String: Any] = ["data": dataDict]

        let response = try await BmobHTTPClient.post(url: url, parameters: requestParams)

        // 旧版 SDK 从 data.results 中提取结果
        guard let data = response["data"] as? [String: Any],
              let results = data["results"] else {
            throw BmobError.serverError(code: -1, message: "Cloud function returned no data")
        }

        return results
    }

    /// 调用云函数（类型安全）
    /// - Parameters:
    ///   - function: 云函数名称
    ///   - params: 参数（可选）
    /// - Returns: Decodable 类型
    public static func run<T: Decodable>(function: String, params: [String: Any]? = nil) async throws -> T {
        let result = try await run(function: function, params: params)

        // 将结果序列化为 JSON Data 再解码
        let jsonData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    /// 调用云函数（无返回值，fire-and-forget）
    /// - Parameters:
    ///   - function: 云函数名称
    ///   - params: 参数
    public static func fire(function: String, params: [String: Any]? = nil) {
        Task {
            _ = try? await run(function: function, params: params)
        }
    }
}

import Foundation

// MARK: - BmobError

/// Bmob SDK 统一错误类型
public enum BmobError: Error, LocalizedError {
    /// SDK 未初始化
    case notInitialized
    /// 初始化失败
    case initializationFailed(reason: String)
    /// 网络错误
    case networkError(underlying: Error)
    /// 服务器返回错误
    case serverError(code: Int, message: String)
    /// 请求超时
    case timeout
    /// 响应解密失败
    case decryptionFailed
    /// 请求加密失败
    case encryptionFailed
    /// JSON 解析失败
    case jsonParsingFailed
    /// 参数无效
    case invalidParameter(reason: String)
    /// 操作不允许
    case operationNotAllowed(reason: String)
    /// 认证失败
    case authenticationFailed
    /// 未知错误
    case unknown(code: Int?, message: String?)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Bmob SDK 尚未初始化，请先调用 Bmob.initialize(appKey:)"
        case .initializationFailed(let reason):
            return "SDK 初始化失败: \(reason)"
        case .networkError(let underlying):
            return "网络错误: \(underlying.localizedDescription)"
        case .serverError(let code, let message):
            return "服务器错误 [\(code)]: \(message)"
        case .timeout:
            return "请求超时"
        case .decryptionFailed:
            return "响应数据解密失败"
        case .encryptionFailed:
            return "请求数据加密失败"
        case .jsonParsingFailed:
            return "JSON 解析失败"
        case .invalidParameter(let reason):
            return "参数无效: \(reason)"
        case .operationNotAllowed(let reason):
            return "操作不允许: \(reason)"
        case .authenticationFailed:
            return "认证失败，请检查 AppKey 或登录状态"
        case .unknown(let code, let message):
            if let code = code, let message = message {
                return "未知错误 [\(code)]: \(message)"
            }
            return "未知错误"
        }
    }

    /// 错误码（兼容旧 SDK）
    public var code: Int {
        switch self {
        case .notInitialized:               return 9001
        case .initializationFailed:         return 9002
        case .networkError:                 return 9003
        case .serverError(let code, _):     return code
        case .timeout:                      return 9004
        case .decryptionFailed:             return 9005
        case .encryptionFailed:             return 9006
        case .jsonParsingFailed:            return 9007
        case .invalidParameter:             return 9008
        case .operationNotAllowed:          return 9009
        case .authenticationFailed:         return 9010
        case .unknown:                      return 9999
        }
    }
}

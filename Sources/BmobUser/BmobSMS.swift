import Foundation
#if canImport(BmobCore)
@_exported import BmobCore
#endif

// MARK: - BmobSMS

/// Bmob 短信服务
///
/// ```swift
/// try await BmobSMS.requestCode(mobilePhoneNumber: "13800138000")
/// try await BmobSMS.verifyCode(mobilePhoneNumber: "13800138000", code: "123456")
/// ```
public enum BmobSMS {

    /// 请求短信验证码
    /// - Parameter mobilePhoneNumber: 手机号
    public static func requestCode(mobilePhoneNumber: String) async throws {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/request_sms_code") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = [
            "mobilePhoneNumber": mobilePhoneNumber
        ]

        _ = try await BmobHTTPClient.post(url: url, parameters: params)
    }

    /// 验证短信验证码
    /// - Parameters:
    ///   - mobilePhoneNumber: 手机号
    ///   - code: 验证码
    public static func verifyCode(mobilePhoneNumber: String, code: String) async throws -> Bool {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/verify_sms_code") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = [
            "mobilePhoneNumber": mobilePhoneNumber,
            "smsCode": code
        ]

        let response = try await BmobHTTPClient.post(url: url, parameters: params)

        if let result = response["result"] as? [String: Any],
           let code = result["code"] as? Int {
            return code == 200
        }

        return false
    }

    /// 查询短信状态
    /// - Parameter smsId: 短信ID
    public static func queryStatus(smsId: String) async throws -> [String: Any] {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/query_sms") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = ["smsId": smsId]
        return try await BmobHTTPClient.post(url: url, parameters: params)
    }
}

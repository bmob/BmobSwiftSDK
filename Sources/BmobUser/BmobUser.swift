import Foundation
#if canImport(BmobCore)
@_exported import BmobCore
@_exported import BmobData
#endif

// MARK: - BmobUser

/// Bmob 用户类，继承自 BmobObject
/// 
/// ```swift
/// let user = BmobUser()
/// user.username = "test"
/// user.password = "pass123"
/// try await user.signUp()
/// 
/// // 登录
/// let loggedIn = try await BmobUser.login(username: "test", password: "pass123")
/// ```
open class BmobUser: BmobObject {

    // MARK: - Static Properties

    private static let currentUserKey = "BmobCurrentUser"
    private static let userDefaultsSuite = "com.bmob.user"

    /// 当前登录用户
    public private(set) static var current: BmobUser?

    // MARK: - User Properties

    /// 用户名
    open var username: String? {
        get { self["username"] as? String }
        set { self["username"] = newValue }
    }

    /// 密码（仅设置时使用，不存储）
    open var password: String? {
        get { self["password"] as? String }
        set { self["password"] = newValue }
    }

    /// 邮箱
    open var email: String? {
        get { self["email"] as? String }
        set { self["email"] = newValue }
    }

    /// 手机号
    open var mobilePhoneNumber: String? {
        get { self["mobilePhoneNumber"] as? String }
        set { self["mobilePhoneNumber"] = newValue }
    }

    /// Session Token
    open var sessionToken: String? {
        get { self["sessionToken"] as? String }
        set { self["sessionToken"] = newValue }
    }

    /// 邮箱是否已验证
    open var emailVerified: Bool {
        get { self["emailVerified"] as? Bool ?? false }
        set { self["emailVerified"] = newValue }
    }

    // MARK: - Initialization

    public init() {
        super.init(className: "_User")
    }

    required public init(className: String, data: [String: Any]) {
        super.init(className: className, data: data)
    }

    // MARK: - Sign Up

    /// 注册新用户
    @discardableResult
    open func signUp() async throws -> BmobUser {
        guard let username = username else {
            throw BmobError.invalidParameter(reason: "username is required")
        }
        guard let password = password else {
            throw BmobError.invalidParameter(reason: "password is required")
        }

        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/signup") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        var userData: [String: Any] = [
            "username": username,
            "password": password
        ]
        if let email = email {
            userData["email"] = email
        }

        let params: [String: Any] = [
            "c": "_User",
            "data": userData
        ]

        let response = try await BmobHTTPClient.post(url: url, parameters: params)
        try updateFromResponse(response)

        BmobUser.saveCurrent(self)
        return self
    }

    // MARK: - Login

    /// 用户名 + 密码登录
    @discardableResult
    public static func login(username: String, password: String) async throws -> BmobUser {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/login") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = [
            "c": "_User",
            "data": [
                "username": username,
                "password": password
            ]
        ]

        let response = try await BmobHTTPClient.post(url: url, parameters: params)
        let user = try userFromResponse(response)
        saveCurrent(user)
        return user
    }

    /// 通用账号登录（用户名/邮箱/手机号）
    @discardableResult
    public static func login(account: String, password: String) async throws -> BmobUser {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/login") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = [
            "c": "_User",
            "data": [
                "username": account,
                "password": password
            ]
        ]

        let response = try await BmobHTTPClient.post(url: url, parameters: params)
        let user = try userFromResponse(response)
        saveCurrent(user)
        return user
    }

    /// 手机号 + 短信验证码登录
    @discardableResult
    public static func login(mobilePhoneNumber: String, smsCode: String) async throws -> BmobUser {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/login") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = [
            "c": "_User",
            "data": [
                "mobilePhoneNumber": mobilePhoneNumber,
                "smsCode": smsCode
            ]
        ]

        let response = try await BmobHTTPClient.post(url: url, parameters: params)
        let user = try userFromResponse(response)
        saveCurrent(user)
        return user
    }

    /// 手机号一键注册登录
    @discardableResult
    public static func signUpOrLogin(mobilePhoneNumber: String, smsCode: String) async throws -> BmobUser {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/login_or_signup") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = [
            "c": "_User",
            "data": [
                "mobilePhoneNumber": mobilePhoneNumber,
                "smsCode": smsCode
            ]
        ]

        let response = try await BmobHTTPClient.post(url: url, parameters: params)
        let user = try userFromResponse(response)
        saveCurrent(user)
        return user
    }

    // MARK: - Logout

    /// 登出
    public static func logout() {
        current = nil
        UserDefaults.standard.removeObject(forKey: currentUserKey)
    }

    // MARK: - Password Management

    /// 更新密码
    open func updatePassword(oldPassword: String, newPassword: String) async throws {
        guard let objectId = objectId else {
            throw BmobError.invalidParameter(reason: "Not logged in")
        }

        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/update_user_password") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = [
            "c": "_User",
            "objectId": objectId,
            "data": [
                "oldPassword": oldPassword,
                "newPassword": newPassword
            ]
        ]

        _ = try await BmobHTTPClient.post(url: url, parameters: params)
    }

    /// 短信重置密码
    public static func resetPassword(smsCode: String, newPassword: String) async throws {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/reset") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = [
            "c": "_User",
            "data": [
                "password": newPassword,
                "smsCode": smsCode
            ]
        ]

        _ = try await BmobHTTPClient.post(url: url, parameters: params)
    }

    /// 邮箱重置密码请求
    public static func requestPasswordReset(email: String) async throws {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/reset") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = [
            "c": "_User",
            "data": ["email": email]
        ]
        _ = try await BmobHTTPClient.post(url: url, parameters: params)
    }

    // MARK: - Email Verification

    /// 请求邮箱验证
    public static func requestEmailVerify(_ email: String) async throws {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/email_verify") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = [
            "c": "_User",
            "data": ["email": email]
        ]
        _ = try await BmobHTTPClient.post(url: url, parameters: params)
    }

    // MARK: - Third-Party Login

    /// 第三方平台
    public enum ThirdPartyPlatform: String {
        case weibo = "weibo"
        case qq = "qq"
        case wechat = "weixin"
    }

    /// 第三方登录
    @discardableResult
    public static func login(platform: ThirdPartyPlatform, authData: [String: Any]) async throws -> BmobUser {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/login") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = [
            "c": "_User",
            "data": [
                "authData": [platform.rawValue: authData]
            ]
        ]

        let response = try await BmobHTTPClient.post(url: url, parameters: params)
        let user = try userFromResponse(response)
        saveCurrent(user)
        return user
    }

    /// 绑定第三方账号
    open func link(platform: ThirdPartyPlatform, authData: [String: Any]) async throws {
        guard let objectId = objectId else {
            throw BmobError.invalidParameter(reason: "Not logged in")
        }
        guard let _ = sessionToken else {
            throw BmobError.authenticationFailed
        }

        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/update") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = [
            "c": "_User",
            "objectId": objectId,
            "data": [
                "authData": [platform.rawValue: authData]
            ]
        ]

        _ = try await BmobHTTPClient.post(url: url, parameters: params)
    }

    /// 解绑第三方账号
    open func unlink(platform: ThirdPartyPlatform) async throws {
        guard let objectId = objectId else {
            throw BmobError.invalidParameter(reason: "Not logged in")
        }

        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/update") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = [
            "c": "_User",
            "objectId": objectId,
            "data": [
                "authData": [platform.rawValue: NSNull()]
            ]
        ]

        _ = try await BmobHTTPClient.post(url: url, parameters: params)
    }

    /// 用当前用户 sessionToken 更新用户信息
    @discardableResult
    open override func update() async throws -> BmobObject {
        guard let objectId = objectId else {
            throw BmobError.invalidParameter(reason: "Not logged in")
        }
        guard let token = sessionToken else {
            throw BmobError.authenticationFailed
        }

        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/update") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let serialized = try BmobSerializer.serialize(data)
        let params: [String: Any] = [
            "c": "_User",
            "objectId": objectId,
            "data": serialized,
            "sessionToken": token
        ]

        let response = try await BmobHTTPClient.post(url: url, parameters: params)

        if let responseData = response["data"] as? [String: Any],
           let updatedAtStr = responseData["updatedAt"] as? String {
            setSystemFields(updatedAt: BmobDateFormatter.date(from: updatedAtStr))
        }

        return self
    }

    // MARK: - Persistence

    /// 恢复当前用户（从本地缓存）
    public static func restoreCurrent() {
        guard let data = UserDefaults.standard.data(forKey: currentUserKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let deserialized = BmobSerializer.deserialize(dict)
        current = BmobUser(className: "_User", data: deserialized)
    }

    /// 保存当前用户到本地
    private static func saveCurrent(_ user: BmobUser) {
        current = user
        let data = try? JSONSerialization.data(withJSONObject: user.fullData)
        UserDefaults.standard.set(data, forKey: currentUserKey)
    }

    // MARK: - Helpers

    private func updateFromResponse(_ response: [String: Any]) throws {
        guard let data = response["data"] as? [String: Any] else {
            throw BmobError.serverError(code: -1, message: "Invalid response")
        }
        let newId = data["objectId"] as? String
        let caStr = data["createdAt"] as? String
        if let token = data["sessionToken"] as? String { sessionToken = token }
        setSystemFields(objectId: newId, createdAt: caStr.flatMap(BmobDateFormatter.date))
    }

    private static func userFromResponse(_ response: [String: Any]) throws -> BmobUser {
        guard let data = response["data"] as? [String: Any] else {
            throw BmobError.serverError(code: -1, message: "Login failed")
        }
        let deserialized = BmobSerializer.deserialize(data)
        return BmobUser(className: "_User", data: deserialized)
    }
}

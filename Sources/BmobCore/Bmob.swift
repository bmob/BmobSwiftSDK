import Foundation

// MARK: - Bmob

/// Bmob SDK 主入口类
/// 提供初始化、域名配置、日志等级等全局控制
public final class Bmob {

    // MARK: - Initialization

    /// 初始化 SDK
    /// - Parameter appKey: Bmob Application ID（如 "933cc5e46af745c6042c328997c3f278"）
    ///
    /// 初始化流程：
    /// 1. Base64(AppKey) → apid
    /// 2. POST /8/secret → 获取 SecretKey（Key1=UserAgent[-16:]，Key2=Response-Id[-16:]）
    /// 3. POST /8/init → 获取域名/migration/时间戳（用 SecretKey 加解密）
    /// 4. 标记 isReady，释放所有排队请求
    ///
    /// 任何步骤失败时，自动调用 markFailed() 通知所有排队请求，避免 `waitUntilReady()` 永久挂起。
    public static func initialize(appKey: String) async throws {
        let manager = BmobManager.shared

        // Step 1: 保存 AppKey（Base64 编码）
        let apid = BmobCrypto.base64EncodeString(appKey)
        await manager.set(apid: apid, appKey: appKey)

        do {
            // Step 2: 获取 SecretKey
            try await fetchSecretKey(appKey: appKey)

            // Step 3: 初始化 SDK
            try await fetchInitConfig()

            // Step 4: 标记完成
            await manager.markReady()
        } catch {
            await manager.markFailed(error)
            throw error
        }
    }

    /// 注册（同步调用，内部启动 async 初始化）
    /// - Parameter appKey: Bmob Application ID
    @MainActor
    public static func register(appKey: String) {
        Task {
            do {
                try await initialize(appKey: appKey)
            } catch {
                print("[BmobSDK] Initialization failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Configuration

    /// 重置 API 域名
    /// - Parameter domain: 自定义域名（需在 initialize 之前调用）
    public static func resetDomain(_ domain: String) {
        Task {
            await BmobManager.shared.setDomain(domain)
        }
    }

    /// 设置请求超时时间
    /// - Parameter timeout: 秒（默认 30）
    public static func setTimeout(_ timeout: TimeInterval) {
        Task {
            await BmobManager.shared.set(timeout: timeout)
        }
    }

    /// SDK 是否已就绪
    public static var isReady: Bool {
        get async {
            await BmobManager.shared.isReady
        }
    }

    // MARK: - Log Level

    /// 日志等级
    public enum LogLevel: Int {
        case none = 0
        case error = 1
        case warn = 2
        case info = 3
        case debug = 4
    }

    /// 当前日志等级
    public static var logLevel: LogLevel = .error

    /// 调试模式：开启后打印详细的请求/响应信息（包括原始 hex、Header 等）
    /// 仅在开发调试时使用，上线前建议关闭
    public static var isDebugEnabled = false

    // MARK: - Private Helpers

    /// 获取 SecretKey
    private static func fetchSecretKey(appKey: String) async throws {
        let manager = BmobManager.shared
        await manager.set(secreting: true)
        defer { Task { await manager.set(secreting: false) } }

        let domain = await manager.apiDomain
        guard let url = URL(string: "\(domain)/8/secret") else {
            throw BmobError.initializationFailed(reason: "Invalid secret URL")
        }

        let parameters: [String: Any] = ["appKey": appKey]

        let response = try await BmobHTTPClient.post(url: url, parameters: parameters, isSecretURL: true)

        guard let data = response["data"] as? [String: Any],
              let secretKeyStr = data["secretKey"] as? String,
              let secretKeyData = secretKeyStr.data(using: .utf8) else {
            let result = response["result"] as? [String: Any]
            let message = result?["message"] as? String ?? "Failed to get secret key"
            throw BmobError.initializationFailed(reason: message)
        }

        await manager.set(secretKey: secretKeyData, secretKeyString: secretKeyStr)

        if logLevel.rawValue >= LogLevel.debug.rawValue {
            print("[BmobSDK] ✅ Secret Key obtained: \(secretKeyStr.prefix(10))...")
        }
    }

    /// 获取初始化配置
    private static func fetchInitConfig() async throws {
        let manager = BmobManager.shared
        await manager.set(initing: true)
        defer { Task { await manager.set(initing: false) } }

        let domain = await manager.apiDomain
        guard let url = URL(string: "\(domain)/8/init") else {
            throw BmobError.initializationFailed(reason: "Invalid init URL")
        }

        let parameters: [String: Any] = [:]

        // 尝试请求，失败则用备用域名重试
        let response: [String: Any]
        do {
            response = try await BmobHTTPClient.post(url: url, parameters: parameters)
        } catch {
            // 重试：使用备用域名
            if logLevel.rawValue >= LogLevel.debug.rawValue {
                print("[BmobSDK] ⚠️ Primary domain failed, retrying with https://open.bmob.site")
            }
            guard let retryURL = URL(string: "https://open.bmob.site/8/init") else {
                throw error
            }
            response = try await BmobHTTPClient.post(url: retryURL, parameters: parameters)
        }

        guard let data = response["data"] as? [String: Any] else {
            throw BmobError.initializationFailed(reason: "Invalid init response")
        }

        // 解析域名
        // 注：保持使用原始域名 open.cctvcloud.cn，不切换到服务端建议的域名
        // （服务端可能返回不可达域名如 open2.bmob.cn）
        if let apiDomain = data["api"] as? String {
            if logLevel.rawValue >= LogLevel.debug.rawValue {
                print("[BmobSDK] ℹ️ Server suggested domain: \(apiDomain), keeping \(domain)")
            }
        }

        if let fileDomain = data["file"] as? String {
            await manager.set(fileDomain: fileDomain)
        }
        if let ioDomain = data["io"] as? String {
            await manager.set(ioDomain: ioDomain)
        }
        if let pushDomain = data["push"] as? String {
            await manager.set(pushDomain: pushDomain)
        }

        // 解析 migration 映射表
        if let migration = data["migration"] as? [String: [Any]] {
            await manager.set(migration: migration)
        }

        // 解析时间戳
        if let serverTimestamp = data["timestamp"] as? Int {
            let clientTime = Int(Date().timeIntervalSince1970)
            let offset = serverTimestamp - clientTime
            await manager.set(timeOffset: offset)
            if logLevel.rawValue >= LogLevel.debug.rawValue {
                print("[BmobSDK] 🕐 Time synced, offset: \(offset)s")
            }
        }

        // 解析又拍云版本
        if let upyunVer = data["upyunVer"] as? Int {
            await manager.set(upyunVersion: upyunVer)
        }
        if let isUp = data["isUp"] as? Bool {
            await manager.set(isCDNEnabled: isUp)
        }

        if logLevel.rawValue >= LogLevel.info.rawValue {
            print("[BmobSDK] ✅ SDK initialized successfully")
        }
    }
}

// MARK: - BmobManager Extended Setter Helpers

extension BmobManager {
    func set(apid: String, appKey: String) {
        self.apid = apid
        self.appKey = appKey
    }

    func set(secretKey: Data, secretKeyString: String) {
        self.secretKey = secretKey
        self.secretKeyString = secretKeyString
    }

    func set(secreting: Bool) {
        isSecreting = secreting
    }

    func set(initing: Bool) {
        isIniting = initing
    }

    func set(timeout: TimeInterval) {
        self.timeout = timeout
    }

    func set(fileDomain: String) {
        self.fileDomain = fileDomain
    }

    func set(ioDomain: String) {
        self.ioDomain = ioDomain
    }

    func set(pushDomain: String) {
        self.pushDomain = pushDomain
    }

    func set(migration: [String: [Any]]) {
        self.migrationMap = migration
    }

    func set(timeOffset: Int) {
        self.timeOffset = timeOffset
    }

    func set(upyunVersion: Int) {
        // 又拍云版本号暂存，文件上传时使用
        UserDefaults.standard.set(upyunVersion, forKey: "BmobUpyunVersion")
    }

    func set(isCDNEnabled: Bool) {
        UserDefaults.standard.set(isCDNEnabled, forKey: "BmobCDNEnabled")
    }
}

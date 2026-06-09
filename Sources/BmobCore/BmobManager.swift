import Foundation

// MARK: - BmobManager

/// SDK 全局状态管理器（actor 确保线程安全）
public actor BmobManager {

    // MARK: - Singleton

    public static let shared = BmobManager()

    // MARK: - Properties

    /// Application ID（Base64(AppKey)）
    var apid: String = ""

    /// 原始 AppKey
    var appKey: String = ""

    /// Secret Key（16 字节）
    var secretKey: Data?

    /// Secret Key 明文（用于加解密）
    var secretKeyString: String?

    /// 服务器时间与本地时间差（秒）
    var timeOffset: Int = 0

    /// 是否已完成初始化
    private(set) var isReady: Bool = false

    /// Secret Key 获取是否进行中
    var isSecreting: Bool = false

    /// 初始化是否进行中
    var isIniting: Bool = false

    // MARK: - Domain Configuration

    /// 默认 API 域名
    static let defaultDomain = "https://open.cctvcloud.cn"

    /// 当前 API 域名
    public var apiDomain: String = BmobManager.defaultDomain

    /// 文件服务器域名
    var fileDomain: String?

    /// Socket.IO 域名
    var ioDomain: String?

    /// 推送服务器域名
    var pushDomain: String?

    /// URL 迁移映射表
    /// 格式: ["action": ["enabled", "path"]]
    var migrationMap: [String: [Any]] = [:]

    // MARK: - Timeout

    /// 请求超时时间（秒）
    var timeout: TimeInterval = 30.0

    // MARK: - Pending Continuations

    /// 初始化完成时等待的 continuations
    private var pendingContinuations: [CheckedContinuation<Void, Error>] = []

    // MARK: - Initialization

    private init() {}

    /// 重置 SDK 状态
    func reset() {
        apid = ""
        appKey = ""
        secretKey = nil
        secretKeyString = nil
        timeOffset = 0
        isReady = false
        isSecreting = false
        isIniting = false
        apiDomain = BmobManager.defaultDomain
        fileDomain = nil
        ioDomain = nil
        pushDomain = nil
        migrationMap = [:]
        pendingContinuations.removeAll()
    }

    /// 设置域名
    func setDomain(_ domain: String) {
        apiDomain = domain
    }

    // MARK: - Init Flow

    /// 完成初始化：标记 ready，释放所有排队请求
    func markReady() {
        isReady = true
        isIniting = false

        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        for cont in continuations {
            cont.resume()
        }
    }

    /// 初始化失败：通知所有排队请求
    func markFailed(_ error: Error) {
        isReady = false
        isIniting = false
        isSecreting = false

        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        for cont in continuations {
            cont.resume(throwing: error)
        }
    }

    /// 等待初始化完成（请求排队）
    public func waitUntilReady() async throws {
        if isReady { return }
        try await withCheckedThrowingContinuation { [weak self] (cont: CheckedContinuation<Void, Error>) in
            Task {
                await self?.addPendingContinuation(cont)
            }
        }
    }

    private func addPendingContinuation(_ cont: CheckedContinuation<Void, Error>) {
        pendingContinuations.append(cont)
    }
}

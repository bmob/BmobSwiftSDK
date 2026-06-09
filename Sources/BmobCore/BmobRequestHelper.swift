import Foundation

// MARK: - BmobRequestHelper

/// 请求辅助工具：生成 User-Agent、Accept-Id、请求体等
enum BmobRequestHelper {

    // MARK: - User-Agent

    /// 生成 User-Agent 字符串
    /// 格式: "{unix_timestamp}{platform}{os_version}"
    /// 例如: "1761040954iOS15.0"
    static func userAgent() -> String {
        let timestamp = String(Int(Date().timeIntervalSince1970))

        #if os(iOS)
        let platform = "iOS"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        // 使用三段式版本号（如 18.0.0），确保 UA 长度 ≥ 18 字节
        // 否则 10位时间戳+"iOS"+"18.0" 仅 17 字节，服务端会拒绝
        let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #elseif os(macOS)
        let platform = "macOS"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #else
        let platform = "unknown"
        let osVersion = "0.0.0"
        #endif

        return "\(timestamp)\(platform)\(osVersion)"
    }

    // MARK: - Accept-Id

    /// 生成 Accept-Id 请求头
    /// Key = IV = UserAgent[1:17]（第2到第18字节，即 index 1..<17）
    /// 对 AppKey 原文进行 AES 加密后 Base64 编码
    static func acceptId(appKey: String) throws -> String {
        let ua = userAgent()
        guard let uaData = ua.data(using: .utf8) else {
            throw BmobError.encryptionFailed
        }

        // 取 UserAgent 的 [1:17] 作为 Key
        let startIndex = 1
        let endIndex = min(uaData.count, 17)
        let keyRange = startIndex..<endIndex

        guard keyRange.count > 0 else {
            throw BmobError.encryptionFailed
        }

        let keyData = uaData.subdata(in: keyRange)

        guard let appKeyData = appKey.data(using: .utf8) else {
            throw BmobError.encryptionFailed
        }

        let encrypted = try BmobCrypto.aesEncrypt(data: appKeyData, key: keyData, iv: keyData)
        return BmobCrypto.base64EncodeData(encrypted)
    }

    // MARK: - Client Info

    /// 生成客户端信息字典（client 字段）
    static func clientInfo() -> [String: Any] {
        var uuid: String
        #if os(iOS)
        uuid = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        uuid = UserDefaults.standard.string(forKey: "BmobDeviceUUID") ?? {
            let newUUID = UUID().uuidString
            UserDefaults.standard.set(newUUID, forKey: "BmobDeviceUUID")
            return newUUID
        }()
        #endif

        let bundleId = Bundle.main.bundleIdentifier ?? "com.bmob.unknown"

        let ex: [String: Any] = [
            "latitude": 0,
            "longitude": 0,
            "uuid": uuid,
            "package": bundleId
        ]

        let caller: String
        #if os(iOS)
        caller = "iOS"
        #elseif os(macOS)
        caller = "macOS"
        #else
        caller = "unknown"
        #endif

        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVer = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

        return [
            "caller": caller,
            "ex": ex,
            "version": osVer
        ]
    }

    // MARK: - AppSign

    /// 生成 appSign
    /// 格式: "{bundleId}/{0或1}"  (0=开发, 1=正式)
    static func appSign() -> String {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.bmob.unknown"
        #if DEBUG
        return "\(bundleId)/0"
        #else
        return "\(bundleId)/1"
        #endif
    }
}

#if os(iOS)
import UIKit
#endif

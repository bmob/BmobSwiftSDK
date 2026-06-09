import Foundation
import CommonCrypto

// MARK: - BmobCrypto

/// Bmob 加密工具集
/// 提供 AES-128-CBC 加解密、HMAC-SHA1 签名、Base64 编解码
public enum BmobCrypto {

    // MARK: - AES-128-CBC

    /// AES-128-CBC 加密
    /// - Parameters:
    ///   - data: 待加密的原始数据
    ///   - key: 加密密钥（取前 16 字节，不足补 \0）
    ///   - iv: 初始向量（取前 16 字节，不足补 \0）
    /// - Returns: 加密后的数据
    public static func aesEncrypt(data: Data, key: Data, iv: Data) throws -> Data {
        let keyBytes = padTo16(key)
        let ivBytes = padTo16(iv)

        return try aesCrypt(operation: CCOperation(kCCEncrypt), data: data, key: keyBytes, iv: ivBytes)
    }

    /// AES-128-CBC 解密
    /// - Parameters:
    ///   - data: 待解密的密文
    ///   - key: 解密密钥（取前 16 字节，不足补 \0）
    ///   - iv: 初始向量（取前 16 字节，不足补 \0）
    /// - Returns: 解密后的数据
    public static func aesDecrypt(data: Data, key: Data, iv: Data) throws -> Data {
        let keyBytes = padTo16(key)
        let ivBytes = padTo16(iv)

        return try aesCrypt(operation: CCOperation(kCCDecrypt), data: data, key: keyBytes, iv: ivBytes)
    }

    /// AES-128-CBC 加密（字符串版本）
    public static func aesEncrypt(string: String, key: String, iv: String) throws -> Data {
        guard let strData = string.data(using: .utf8),
              let keyData = key.data(using: .utf8),
              let ivData = iv.data(using: .utf8) else {
            throw BmobCryptoError.invalidUTF8Encoding
        }
        return try aesEncrypt(data: strData, key: keyData, iv: ivData)
    }

    /// AES-128-CBC 解密（字符串版本）
    public static func aesDecrypt(data: Data, key: String, iv: String) throws -> Data {
        guard let keyData = key.data(using: .utf8),
              let ivData = iv.data(using: .utf8) else {
            throw BmobCryptoError.invalidUTF8Encoding
        }
        return try aesDecrypt(data: data, key: keyData, iv: ivData)
    }

    // MARK: - HMAC-SHA1

    /// HMAC-SHA1 签名
    /// - Parameters:
    ///   - data: 待签名的数据
    ///   - key: 签名密钥
    /// - Returns: HMAC-SHA1 签名结果（20 字节）
    public static func hmacSHA1(data: Data, key: Data) -> Data {
        var result = Data(count: Int(CC_SHA1_DIGEST_LENGTH))
        result.withUnsafeMutableBytes { resultBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA1),
                        keyBytes.baseAddress,
                        key.count,
                        dataBytes.baseAddress,
                        data.count,
                        resultBytes.baseAddress
                    )
                }
            }
        }
        return result
    }

    // MARK: - Base64

    /// Base64 编码（`+` 替换为 `%2B`，用于 apid 编码）
    public static func base64Encode(_ data: Data) -> String {
        let encoded = data.base64EncodedString()
        return encoded.replacingOccurrences(of: "+", with: "%2B")
    }

    /// Base64 编码（不做 `%2B` 替换，用于请求体/Accept-Id 编码，与后端协议一致）
    public static func base64EncodeData(_ data: Data) -> String {
        return data.base64EncodedString()
    }

    /// Base64 解码（自动处理 `%2B` → `+`）
    public static func base64Decode(_ string: String) -> Data? {
        let normalized = string.replacingOccurrences(of: "%2B", with: "+")
        return Data(base64Encoded: normalized)
    }

    /// Base64 编码字符串
    public static func base64EncodeString(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return string }
        return base64Encode(data)
    }

    /// Base64 解码为字符串
    public static func base64DecodeString(_ string: String) -> String? {
        guard let data = base64Decode(string) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - SHA-256 (MD5 命名兼容旧代码)

    /// SHA-256 哈希（旧代码中命名为 MD5，实际为 SHA-256）
    public static func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        var hash = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        hash.withUnsafeMutableBytes { hashBytes in
            data.withUnsafeBytes { dataBytes in
                CC_SHA256(dataBytes.baseAddress, CC_LONG(data.count), hashBytes.baseAddress)
            }
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private Helpers

    private static func padTo16(_ data: Data) -> Data {
        if data.count >= 16 {
            return data.prefix(16)
        }
        var padded = Data(data)
        padded.append(contentsOf: [UInt8](repeating: 0, count: 16 - data.count))
        return padded
    }

    private static func aesCrypt(operation: CCOperation, data: Data, key: Data, iv: Data) throws -> Data {
        let dataLength = data.count
        let bufferSize = dataLength + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var numBytesProcessed: size_t = 0

        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                data.withUnsafeBytes { dataBytes in
                    buffer.withUnsafeMutableBytes { bufferBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, kCCBlockSizeAES128,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, dataLength,
                            bufferBytes.baseAddress, bufferSize,
                            &numBytesProcessed
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw BmobCryptoError.aesCryptFailed(status: Int(status))
        }

        return buffer.prefix(numBytesProcessed)
    }
}

// MARK: - BmobCryptoError

public enum BmobCryptoError: Error {
    case invalidUTF8Encoding
    case aesCryptFailed(status: Int)
    case base64DecodeFailed
    case invalidKeyLength
}

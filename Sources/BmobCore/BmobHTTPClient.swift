import Foundation

// MARK: - BmobHTTPClient

/// Bmob HTTP 客户端
/// 基于 URLSession async/await，自动处理请求加密/响应解密
public enum BmobHTTPClient {

    /// 发送 POST 请求（加密传输）
    /// - Parameters:
    ///   - url: 请求 URL
    ///   - parameters: 请求参数字典
    ///   - isSecretURL: 是否为 /8/secret 端点（使用特殊密钥）
    /// - Returns: 解密后的响应 JSON 字典
    public static func post(url: URL, parameters: [String: Any], isSecretURL: Bool = false) async throws -> [String: Any] {
        let manager = BmobManager.shared

        // 序列化参数
        var requestParams = parameters

        // 非 secret 请求：添加 client、v、appSign、timestamp
        if !isSecretURL {
            requestParams["client"] = BmobRequestHelper.clientInfo()
            requestParams["v"] = "v2.4.1"
            requestParams["appSign"] = BmobRequestHelper.appSign()

            let clientTime = Int(Date().timeIntervalSince1970)
            let timeOffset = await manager.timeOffset
            requestParams["timestamp"] = clientTime + timeOffset
        }

        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: requestParams, options: [])
        } catch {
            throw BmobError.jsonParsingFailed
        }

        // 调试：打印加密前的请求 JSON
        if Bmob.isDebugEnabled {
            if let jsonStr = String(data: jsonData, encoding: .utf8) {
                let maxLen = min(jsonStr.count, 500)
                let preview = String(jsonStr.prefix(maxLen))
                print("📤 [HTTP] POST \(url.lastPathComponent): \(preview)\(jsonStr.count > maxLen ? "..." : "")")
            }
        }

        // 加密请求体
        let ua = BmobRequestHelper.userAgent()
        guard let uaData = ua.data(using: .utf8) else {
            throw BmobError.encryptionFailed
        }

        let encryptedBody: String
        let acceptId: String?

        if isSecretURL {
            // Secret 端点：Key1 = UserAgent[-16:]
            let key1 = uaData.suffix(16)
            let encrypted = try BmobCrypto.aesEncrypt(data: jsonData, key: key1, iv: key1)
            encryptedBody = BmobCrypto.base64EncodeData(encrypted)
            acceptId = nil
        } else {
            // 普通请求：用 SecretKey 加密
            guard let sk = await manager.secretKey else {
                throw BmobError.notInitialized
            }
            let encrypted = try BmobCrypto.aesEncrypt(data: jsonData, key: sk, iv: sk)
            encryptedBody = BmobCrypto.base64EncodeData(encrypted)

            // 生成 Accept-Id
            let appKey = await manager.appKey
            acceptId = try BmobRequestHelper.acceptId(appKey: appKey)
        }

        // 构造请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = encryptedBody.data(using: .utf8)
        request.setValue("text/html;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        if let acceptId = acceptId {
            request.setValue(acceptId, forHTTPHeaderField: "Accept-Id")
        }

        // 调试：打印请求详情
        if Bmob.isDebugEnabled {
            print("🌐 [HTTP] URL: \(url.absoluteString)")
            print("🌐 [HTTP] User-Agent: \(ua) (len=\(ua.count))")
            print("🌐 [HTTP] Key1 (UA[-16:]): \(String(data: uaData.suffix(16), encoding: .utf8) ?? "nil")")
            print("🌐 [HTTP] encryptedBody len: \(encryptedBody.count), prefix: \(String(encryptedBody.prefix(min(40, encryptedBody.count))))")
        }

        let timeout = await manager.timeout
        request.timeoutInterval = timeout

        // 发送请求（使用不自动 Accept-Encoding 的 session，避免服务端 gzip 压缩导致 body 无法读取）
        let (data, response): (Data, URLResponse)
        do {
            let config = URLSessionConfiguration.default
            // 覆盖默认的 Accept-Encoding，阻止服务端 gzip 压缩响应
            config.httpAdditionalHeaders = ["Accept-Encoding": "identity"]
            let session = URLSession(configuration: config)
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw BmobError.timeout
        } catch {
            throw BmobError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BmobError.networkError(underlying: NSError(domain: "", code: -1))
        }

        // 调试：打印原始响应信息
        if Bmob.isDebugEnabled {
            print("📥 [HTTP] \(url.lastPathComponent) statusCode=\(httpResponse.statusCode)")
            print("📥 [HTTP] data.count=\(data.count)")
            print("📥 [HTTP] Content-Length=\(httpResponse.allHeaderFields["Content-Length"] ?? "nil")")
            print("📥 [HTTP] Content-Encoding=\(httpResponse.allHeaderFields["Content-Encoding"] ?? "nil")")
            print("📥 [HTTP] allHeaders:")
            for (key, value) in httpResponse.allHeaderFields {
                print("📥 [HTTP]   \(key): \(value)")
            }
            print("📥 [HTTP] body raw: \(data.prefix(200) as NSData)")
            if let bodyStr = String(data: data, encoding: .utf8) {
                print("📥 [HTTP] body utf8: \(String(bodyStr.prefix(500)))")
            }
        }

        // 解密响应
        var decryptedData: Data
        if isSecretURL {
            // Secret 端点：Key2 = Response-Id[-16:]
            guard let responseId = httpResponse.allHeaderFields["Response-Id"] as? String,
                  responseId.count >= 16 else {
                if Bmob.isDebugEnabled {
                    let respIdValue = httpResponse.allHeaderFields["Response-Id"]
                    print("📥 [HTTP] ❌ Secret 解密前置失败: Response-Id=\(String(describing: respIdValue))")
                    print("📥 [HTTP]    可能原因: 服务端返回了错误（非加密响应），statusCode=\(httpResponse.statusCode)")
                }
                throw BmobError.decryptionFailed
            }
            let key2 = String(responseId.suffix(16))
            guard let key2Data = key2.data(using: .utf8),
                  let bodyString = String(data: data, encoding: .utf8),
                  let decoded = BmobCrypto.base64Decode(bodyString) else {
                throw BmobError.decryptionFailed
            }
            decryptedData = try BmobCrypto.aesDecrypt(data: decoded, key: key2Data, iv: key2Data)
        } else {
            // 普通响应：用 SecretKey 解密
            guard let sk = await manager.secretKey,
                  let dataString = String(data: data, encoding: .utf8),
                  let decoded = BmobCrypto.base64Decode(dataString) else {
                // 尝试用 Error Key 解密
                if let dataString = String(data: data, encoding: .utf8),
                   let uaData = ua.data(using: .utf8),
                   uaData.count >= 17 {
                    let errorKey = uaData.subdata(in: 1..<17)
                    if let decoded = BmobCrypto.base64Decode(dataString) {
                        do {
                            decryptedData = try BmobCrypto.aesDecrypt(data: decoded, key: errorKey, iv: errorKey)
                            // 如果成功，继续解析（可能是错误响应）
                        } catch {
                            throw BmobError.decryptionFailed
                        }
                    } else {
                        throw BmobError.decryptionFailed
                    }
                } else {
                    throw BmobError.decryptionFailed
                }
                return try parseResponse(data: decryptedData, statusCode: httpResponse.statusCode)
            }
            decryptedData = try BmobCrypto.aesDecrypt(data: decoded, key: sk, iv: sk)
        }

        // 解析 JSON 响应
        return try parseResponse(data: decryptedData, statusCode: httpResponse.statusCode)
    }

    // MARK: - Private

    private static func parseResponse(data: Data, statusCode: Int) throws -> [String: Any] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw BmobError.jsonParsingFailed
        }

        guard let dict = json as? [String: Any] else {
            throw BmobError.jsonParsingFailed
        }

        // 调试：打印解密后的响应
        if Bmob.isDebugEnabled {
            if let jsonStr = String(data: (try? JSONSerialization.data(withJSONObject: dict, options: [])) ?? Data(), encoding: .utf8) {
                let maxLen = min(jsonStr.count, 300)
                print("📥 [HTTP] 响应: \(String(jsonStr.prefix(maxLen)))\(jsonStr.count > maxLen ? "..." : "")")
            }
        }

        // 检查服务端返回码
        if let result = dict["result"] as? [String: Any],
           let code = result["code"] as? Int,
           code != 200 {
            let message = result["message"] as? String ?? "Unknown error"
            throw BmobError.serverError(code: code, message: message)
        }

        if statusCode != 200 {
            throw BmobError.serverError(code: statusCode, message: "HTTP \(statusCode)")
        }

        return dict
    }
}

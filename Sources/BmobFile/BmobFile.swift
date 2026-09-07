import Foundation
#if canImport(BmobCore)
@_exported import BmobCore
@_exported import BmobData
#endif

// MARK: - BmobFile

/// Bmob 文件管理
///
/// ```swift
/// let file = BmobFile(data: imageData, filename: "photo.jpg")
/// try await file.upload { progress in
///     print("Upload: \(Int(progress * 100))%")
/// }
/// ```
public class BmobFile {

    // MARK: - Properties

    /// 文件数据
    public let data: Data

    /// 文件名
    public let filename: String

    /// 文件 URL（上传后赋值）
    public internal(set) var url: String?

    /// CDN 标识（上传后赋值，删除时使用）
    public internal(set) var cdn: String?

    /// MIME 类型
    public var mimeType: String?

    // MARK: - Initialization

    /// 通过 Data 创建
    public init(data: Data, filename: String, mimeType: String? = nil) {
        self.data = data
        self.filename = filename
        self.mimeType = mimeType ?? BmobFile.mimeTypeFor(filename: filename)
    }

    /// 通过本地文件路径创建
    public convenience init?(filePath: String) {
        let url = URL(fileURLWithPath: filePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data, filename: url.lastPathComponent)
    }

    /// 通过 URL 字符串创建（用于已上传文件）
    public init?(url: String, cdn: String? = nil) {
        guard let fileURL = URL(string: url) else { return nil }
        self.data = Data()
        self.filename = fileURL.lastPathComponent
        self.url = url
        self.cdn = cdn
        self.mimeType = BmobFile.mimeTypeFor(filename: filename)
    }

    // MARK: - Upload

    /// 上传文件（`POST /8/files`）
    ///
    /// 鉴权与其他 `/8/*` 接口一致；请求体为 `{加密JSON}&&{文件Base64}`。
    /// - Parameter progress: 进度回调（0.0 ~ 1.0）
    @discardableResult
    public func upload(progress: ((Double) -> Void)? = nil) async throws -> BmobFile {
        if data.isEmpty {
            throw BmobError.invalidParameter(reason: "File data is empty")
        }

        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/files") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let parameters: [String: Any] = [
            "c": "File",
            "data": [
                "filename": filename
            ]
        ]

        let response = try await BmobHTTPClient.uploadFile(
            url: url,
            parameters: parameters,
            fileData: data,
            progress: progress
        )

        guard let responseData = response["data"] as? [String: Any] else {
            throw BmobError.serverError(code: -1, message: "Invalid upload response")
        }

        guard let fileUrl = responseData["url"] as? String, !fileUrl.isEmpty else {
            throw BmobError.jsonParsingFailed
        }

        self.url = fileUrl
        if let cdn = responseData["cdn"] as? String {
            self.cdn = cdn
        }

        return self
    }

    // MARK: - Batch Upload

    /// 批量上传
    /// - Parameter files: 文件数组
    /// - Returns: 上传后的 BmobFile 数组
    public static func uploadBatch(_ files: [BmobFile], progress: ((Double) -> Void)? = nil) async throws -> [BmobFile] {
        var uploaded: [BmobFile] = []
        for (index, file) in files.enumerated() {
            try await file.upload()
            uploaded.append(file)
            progress?(Double(index + 1) / Double(files.count))
        }
        return uploaded
    }

    // MARK: - Delete

    /// 删除文件（`POST /8/delcdnupload`）
    ///
    /// `/8/files` 转发到 restful `/2/files`，删除对应使用 `/8/delcdnupload`。
    public func delete() async throws {
        guard let fileURL = url else {
            throw BmobError.invalidParameter(reason: "File URL is nil")
        }

        let domain = await BmobManager.shared.apiDomain
        guard let requestURL = URL(string: "\(domain)/8/delcdnupload") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let path = BmobFile.cdnPath(from: fileURL)
        let cdnName = cdn ?? "upyun"

        let params: [String: Any] = [
            "data": [
                "filename": path,
                "cdn": cdnName
            ]
        ]

        _ = try await BmobHTTPClient.post(url: requestURL, parameters: params)
        self.url = nil
        self.cdn = nil
    }

    /// 批量删除
    public static func deleteBatch(urls: [String]) async throws {
        for fileURL in urls {
            let file = BmobFile(url: fileURL)
            try await file?.delete()
        }
    }

    // MARK: - BmobObject Integration

    /// 返回 File 类型的字典（用于 BmobObject 赋值）
    public func fileDict(filename: String) -> [String: Any] {
        var dict: [String: Any] = [
            "__type": "File",
            "url": url ?? ""
        ]
        if !filename.isEmpty {
            dict["filename"] = filename
        }
        return dict
    }

    // MARK: - Private Helpers

    /// 从完整 CDN URL 提取删除所需路径（去掉 scheme + host）
    static func cdnPath(from fileURL: String) -> String {
        guard let parsed = URL(string: fileURL),
              let host = parsed.host else {
            return fileURL.hasPrefix("/") ? fileURL : "/\(fileURL)"
        }

        var path = fileURL
        for scheme in ["https://", "http://"] {
            let prefix = "\(scheme)\(host)"
            if let range = path.range(of: prefix) {
                path = String(path[range.upperBound...])
                break
            }
        }

        if path.isEmpty {
            return "/"
        }
        return path.hasPrefix("/") ? path : "/\(path)"
    }

    /// 根据文件名推断 MIME 类型
    static func mimeTypeFor(filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "html", "htm": return "text/html"
        case "json": return "application/json"
        case "mp4": return "video/mp4"
        case "mp3": return "audio/mpeg"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }
}

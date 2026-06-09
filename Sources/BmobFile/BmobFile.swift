import Foundation
import BmobCore
import BmobData

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
    public init?(url: String) {
        guard let fileURL = URL(string: url) else { return nil }
        self.data = Data()
        self.filename = fileURL.lastPathComponent
        self.url = url
        self.mimeType = BmobFile.mimeTypeFor(filename: filename)
    }

    // MARK: - Upload

    /// 上传文件
    /// - Parameter progress: 进度回调（0.0 ~ 1.0）
    @discardableResult
    public func upload(progress: ((Double) -> Void)? = nil) async throws -> BmobFile {
        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/cdn") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        // 构造 multipart 上传
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = buildMultipartBody(boundary: boundary)
        request.httpBody = body

        // 使用 URLSession 的 delegate 模式获取进度
        let delegate = ProgressDelegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let (responseData, response): (Data, URLResponse)
        do {
            (responseData, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw BmobError.timeout
        } catch {
            throw BmobError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BmobError.serverError(code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                                         message: "Upload failed")
        }

        let json = try JSONSerialization.jsonObject(with: responseData)
        guard let dict = json as? [String: Any],
              let fileUrl = dict["url"] as? String ?? dict["cdn"] as? String else {
            throw BmobError.jsonParsingFailed
        }

        self.url = fileUrl
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

    /// 删除文件
    public func delete() async throws {
        guard let fileURL = url else {
            throw BmobError.invalidParameter(reason: "File URL is nil")
        }

        let domain = await BmobManager.shared.apiDomain
        guard let url = URL(string: "\(domain)/8/cdn") else {
            throw BmobError.notInitialized
        }

        try await BmobManager.shared.waitUntilReady()

        let params: [String: Any] = [
            "url": fileURL,
            "action": "delete"
        ]

        _ = try await BmobHTTPClient.post(url: url, parameters: params)
        self.url = nil
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

    private func buildMultipartBody(boundary: String) -> Data {
        var body = Data()

        let lineBreak = "\r\n"
        let boundaryPrefix = "--\(boundary)\(lineBreak)"

        // file 字段
        if let boundaryData = boundaryPrefix.data(using: .utf8) { body.append(boundaryData) }
        let disposition = "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\(lineBreak)"
        if let disData = disposition.data(using: .utf8) { body.append(disData) }
        let contentType = "Content-Type: \(mimeType ?? "application/octet-stream")\(lineBreak)\(lineBreak)"
        if let ctData = contentType.data(using: .utf8) { body.append(ctData) }

        body.append(data)
        if let lbData = lineBreak.data(using: .utf8) { body.append(lbData) }

        // 结束边界
        let endBoundary = "--\(boundary)--\(lineBreak)"
        if let endData = endBoundary.data(using: .utf8) { body.append(endData) }

        return body
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

// MARK: - ProgressDelegate

private final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
    let progress: ((Double) -> Void)?

    init(progress: ((Double) -> Void)?) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        progress?(fraction)
    }
}

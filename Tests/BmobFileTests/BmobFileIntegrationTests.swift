import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import BmobFile
@testable import BmobCore

/// BmobFile 文件上传/删除集成测试
/// 测试密钥: 89e65e889367ea647974b90f3338b06d
final class BmobFileIntegrationTests: XCTestCase {

    // MARK: - Test Key

    private let testAppKey = "89e65e889367ea647974b90f3338b06d"

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        await BmobManager.shared.reset()
        do {
            try await Bmob.initialize(appKey: testAppKey)
        } catch {
            XCTFail("SDK 初始化失败: \(error.localizedDescription)")
            throw error
        }
    }

    override func tearDown() async throws {
        await BmobManager.shared.reset()
        try await super.tearDown()
    }

    // MARK: - Upload Tests

    func testUploadTextFile() async throws {
        let content = "Hello Bmob Swift SDK! Test at \(Date())"
        guard let data = content.data(using: .utf8) else {
            XCTFail("无法生成测试数据")
            return
        }

        let file = BmobFile(data: data, filename: "test_upload_\(Int(Date().timeIntervalSince1970)).txt")

        do {
            let uploaded = try await file.upload()
            XCTAssertNotNil(uploaded.url, "上传后应有 URL")
            XCTAssertTrue(uploaded.url?.isEmpty == false, "URL 不应为空")

            // 验证 MIME 类型
            XCTAssertEqual(uploaded.mimeType, "text/plain")

            // 清理：删除上传的文件
            if let url = uploaded.url {
                try? await uploaded.delete()
            }
        } catch let error as BmobError {
            XCTFail("文件上传失败: \(error.localizedDescription)")
        }
    }

    func testUploadImageFile() async throws {
        // 生成 64x64 彩色渐变 PNG
        let pngData = generateTestPNG()
        XCTAssertFalse(pngData.isEmpty, "彩色测试图应生成成功")
        let name = "test_color_image_\(Int(Date().timeIntervalSince1970)).png"
        let file = BmobFile(data: pngData, filename: name)

        do {
            let uploaded = try await file.upload()
            XCTAssertNotNil(uploaded.url)
            XCTAssertEqual(uploaded.mimeType, "image/png")

            // 保留文件便于在控制台核对；需要清理时取消下面注释
            print("✅ 彩色图片已上传 filename=\(name) bytes=\(pngData.count)")
            print("✅ url=\(uploaded.url ?? "")")
            print("✅ cdn=\(uploaded.cdn ?? "")")
            // try? await uploaded.delete()
        } catch let error as BmobError {
            XCTFail("图片上传失败: \(error.localizedDescription)")
        }
    }

    func testUploadWithProgressCallback() async throws {
        let content = String(repeating: "ABCDEFGHIJ", count: 500) // ~5KB
        guard let data = content.data(using: .utf8) else {
            XCTFail("无法生成测试数据")
            return
        }

        let file = BmobFile(data: data, filename: "test_progress_\(Int(Date().timeIntervalSince1970)).txt")

        var progressValues: [Double] = []
        let progressExpectation = expectation(description: "Progress reported")
        progressExpectation.assertForOverFulfill = false

        do {
            let uploaded = try await file.upload { progress in
                progressValues.append(progress)
                if progress >= 1.0 {
                    progressExpectation.fulfill()
                }
            }

            XCTAssertNotNil(uploaded.url)
            XCTAssertFalse(progressValues.isEmpty, "应有进度回调")

            // 如果进度在完成前就已上报，等待完成
            await fulfillment(of: [progressExpectation], timeout: 5)

            // 清理
            try? await uploaded.delete()
        } catch let error as BmobError {
            XCTFail("带进度上传失败: \(error.localizedDescription)")
        }
    }

    func testUploadEmptyFile() async throws {
        let file = BmobFile(data: Data(), filename: "empty_test.txt")

        do {
            _ = try await file.upload()
            XCTFail("空文件不应上传成功")
        } catch let error as BmobError {
            // SDK 本地拒绝空文件，或服务端返回 file 相关错误
            switch error {
            case .invalidParameter:
                XCTAssertTrue(true)
            case .serverError:
                XCTAssertTrue(true)
            default:
                XCTFail("空文件上传异常: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Delete Tests

    func testDeleteUploadedFile() async throws {
        // 先上传
        let content = "File to be deleted"
        guard let data = content.data(using: .utf8) else {
            XCTFail("无法生成测试数据")
            return
        }

        let file = BmobFile(data: data, filename: "to_delete_\(Int(Date().timeIntervalSince1970)).txt")
        var uploaded: BmobFile?
        do {
            uploaded = try await file.upload()
            XCTAssertNotNil(uploaded?.url)
        } catch {
            XCTFail("上传失败: \(error.localizedDescription)")
            return
        }

        // 删除
        do {
            try await uploaded?.delete()
            XCTAssertNil(uploaded?.url, "删除后 url 应为 nil")
        } catch let error as BmobError {
            XCTFail("删除文件失败: \(error.localizedDescription)")
        }
    }

    // MARK: - MIME Type Detection Tests

    func testMimeTypeDetection() {
        XCTAssertEqual(BmobFile.mimeTypeFor(filename: "photo.jpg"), "image/jpeg")
        XCTAssertEqual(BmobFile.mimeTypeFor(filename: "photo.jpeg"), "image/jpeg")
        XCTAssertEqual(BmobFile.mimeTypeFor(filename: "photo.png"), "image/png")
        XCTAssertEqual(BmobFile.mimeTypeFor(filename: "doc.pdf"), "application/pdf")
        XCTAssertEqual(BmobFile.mimeTypeFor(filename: "data.json"), "application/json")
        XCTAssertEqual(BmobFile.mimeTypeFor(filename: "note.txt"), "text/plain")
        XCTAssertEqual(BmobFile.mimeTypeFor(filename: "video.mp4"), "video/mp4")
        XCTAssertEqual(BmobFile.mimeTypeFor(filename: "music.mp3"), "audio/mpeg")
        XCTAssertEqual(BmobFile.mimeTypeFor(filename: "archive.zip"), "application/zip")
        XCTAssertEqual(BmobFile.mimeTypeFor(filename: "unknown.xyz"), "application/octet-stream")
        XCTAssertEqual(BmobFile.mimeTypeFor(filename: "no_extension"), "application/octet-stream")
    }

    // MARK: - File Object Integration Tests

    func testFileDictionaryForBmobObject() {
        let file = BmobFile(data: Data(), filename: "test.png")
        file.url = "http://file.bmob.cn/test.png"

        let dict = file.fileDict(filename: "test.png")
        XCTAssertEqual(dict["__type"] as? String, "File")
        XCTAssertEqual(dict["url"] as? String, "http://file.bmob.cn/test.png")
        XCTAssertEqual(dict["filename"] as? String, "test.png")
    }

    func testFileInitWithUrl() {
        let file = BmobFile(url: "http://file.bmob.cn/example.txt")
        XCTAssertNotNil(file)
        XCTAssertEqual(file?.url, "http://file.bmob.cn/example.txt")
        XCTAssertEqual(file?.filename, "example.txt")
    }

    func testFileInitWithInvalidUrl() {
        let file = BmobFile(url: "not a valid url")
        // Invalid URL should also work since it can be created from string
    }

    // MARK: - Helpers

    /// 生成 64x64 彩色渐变 PNG（红→黄→绿→青→蓝→品红）
    private func generateTestPNG() -> Data {
        let width = 64
        let height = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Data()
        }

        for x in 0..<width {
            let hue = CGFloat(x) / CGFloat(width)
            let (r, g, b) = hsvToRGB(h: hue, s: 1.0, v: 1.0)
            context.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }

        // 中间画一条白色横带，便于肉眼确认上传图不是纯色块
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.85)
        context.fill(CGRect(x: 0, y: height / 2 - 4, width: width, height: 8))

        guard let cgImage = context.makeImage() else { return Data() }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return data as Data
    }

    private func hsvToRGB(h: CGFloat, s: CGFloat, v: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let i = Int(h * 6)
        let f = h * 6 - CGFloat(i)
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        switch i % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}

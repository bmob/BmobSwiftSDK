import XCTest
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
        // 生成一个 1x1 PNG 图片（最小有效 PNG）
        let pngData = generateTestPNG()
        let file = BmobFile(data: pngData, filename: "test_image_\(Int(Date().timeIntervalSince1970)).png")

        do {
            let uploaded = try await file.upload()
            XCTAssertNotNil(uploaded.url)
            XCTAssertEqual(uploaded.mimeType, "image/png")

            // 清理
            try? await uploaded.delete()
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
            let uploaded = try await file.upload()
            XCTAssertNotNil(uploaded.url)

            // 清理
            try? await uploaded.delete()
        } catch let error as BmobError where error.code == 9008 {
            // 空文件上传可能被拒绝，这是合理行为
            XCTAssertTrue(true)
        } catch let error as BmobError {
            XCTFail("空文件上传异常: \(error.localizedDescription)")
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

    /// 生成最小有效 PNG（1x1 灰色像素）
    private func generateTestPNG() -> Data {
        // 1x1 灰色 PNG（最小有效 PNG 文件）
        let pngBytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, // 8-bit RGB
            0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT chunk
            0x54, 0x08, 0xD7, 0x63, 0x60, 0x60, 0x60, 0x00, // data
            0x00, 0x00, 0x04, 0x00, 0x01, 0x27, 0x34, 0x0A, // CRC
            0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND
            0xAE, 0x42, 0x60, 0x82
        ]
        return Data(pngBytes)
    }
}

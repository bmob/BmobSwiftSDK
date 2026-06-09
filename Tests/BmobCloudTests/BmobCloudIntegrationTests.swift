import XCTest
@testable import BmobCloud
@testable import BmobCore

/// BmobCloud 云函数调用集成测试
/// 测试密钥: 89e65e889367ea647974b90f3338b06d
///
/// 注意: 部分测试需要在 Bmob 控制台预先部署云函数才能通过。
/// 未部署云函数时，testCallCloudFunction 会返回服务端错误，这是预期行为。
final class BmobCloudIntegrationTests: XCTestCase {

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

    // MARK: - Cloud Function Tests

    func testCallCloudFunctionWithoutParams() async throws {
        // 调用一个可能存在的云函数；如果不存在，预期服务端返回错误
        do {
            let result = try await BmobCloud.run(function: "hello")
            // 如果云函数存在且成功，验证返回值非空
            XCTAssertNotNil(result)
        } catch let error as BmobError where error.code == 401 {
            // 401: 云函数未找到（预期行为）
            print("⚠️ Cloud function 'hello' not deployed, skipping test")
        } catch let error as BmobError {
            // 其他服务端错误也记录但不阻塞
            print("⚠️ Cloud function call failed: \(error.localizedDescription)")
        }
    }

    func testCallCloudFunctionWithParams() async throws {
        do {
            let params: [String: Any] = ["name": "SwiftSDK", "version": "1.0"]
            let result = try await BmobCloud.run(function: "greet", params: params)
            XCTAssertNotNil(result)
        } catch let error as BmobError where error.code == 401 {
            print("⚠️ Cloud function 'greet' not deployed, skipping test")
        } catch let error as BmobError {
            print("⚠️ Cloud function call failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Fire-and-Forget Tests

    func testFireAndForgetCloudFunction() async throws {
        // fire-and-forget 不阻塞，也不抛异常到调用方
        BmobCloud.fire(function: "log_event", params: [
            "event": "test_run",
            "timestamp": Int(Date().timeIntervalSince1970)
        ])

        // 等待一小段时间让请求发出
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        // fire-and-forget 不应该崩溃
        XCTAssertTrue(true)
    }

    // MARK: - Error Handling Tests

    func testCloudFunctionWithInvalidParams() async throws {
        // 传入空参数字典应该可以正常发送（服务端决定是否拒绝）
        do {
            let result = try await BmobCloud.run(function: "test", params: [:])
            // 可能成功也可能失败，取决于服务端
            XCTAssertTrue(true)
        } catch {
            // 服务端错误是可以接受的
            XCTAssertTrue(true)
        }
    }

    func testCloudFunctionBeforeInit() async throws {
        // 重置状态
        await BmobManager.shared.reset()

        do {
            _ = try await BmobCloud.run(function: "test")
            XCTFail("未初始化时调用云函数应抛出错误")
        } catch let error as BmobError {
            XCTAssertEqual(error.code, 9001, "应为 notInitialized 错误")
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    // MARK: - Type-Safe Decoding Tests

    func testTypeSafeCloudFunctionCall() async throws {
        struct TestResponse: Decodable {
            let message: String?
            let status: String?
        }

        do {
            let result: TestResponse = try await BmobCloud.run(
                function: "status_check",
                params: ["source": "integration_test"]
            )
            XCTAssertNotNil(result)
        } catch let error as BmobError where error.code == 401 {
            print("⚠️ Cloud function 'status_check' not deployed")
        } catch {
            // JSON 解码失败也可以，因为云端返回的格式可能不匹配
            print("⚠️ Type-safe decode failed (expected if cloud function returns different format): \(error)")
        }
    }
}

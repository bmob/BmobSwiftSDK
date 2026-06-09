import XCTest
@testable import BmobUser
@testable import BmobCore

/// BmobUser 认证流程集成测试
/// 测试密钥: 89e65e889367ea647974b90f3338b06d
/// 使用唯一用户名避免冲突
final class BmobUserIntegrationTests: XCTestCase {

    // MARK: - Test Key

    private let testAppKey = "89e65e889367ea647974b90f3338b06d"

    // 生成唯一测试用户名（毫秒级 + 随机数，避免并发测试冲突）
    private static var counter = 0
    private var testUsername: String {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        Self.counter += 1
        return "swift_test_\(ts)_\(Self.counter)"
    }

    private var testPassword: String {
        "test_password_123"
    }

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        // 重新初始化 SDK 以清除旧状态
        await BmobManager.shared.reset()
        do {
            try await Bmob.initialize(appKey: testAppKey)
        } catch {
            XCTFail("SDK 初始化失败: \(error.localizedDescription)")
            throw error
        }
    }

    override func tearDown() async throws {
        // 登出
        BmobUser.logout()
        await BmobManager.shared.reset()
        try await super.tearDown()
    }

    // MARK: - Registration Tests

    func testSignUpWithUsernameAndPassword() async throws {
        let user = BmobUser()
        user.username = testUsername
        user.password = testPassword

        do {
            let savedUser = try await user.signUp()
            XCTAssertNotNil(savedUser.objectId, "注册后应有 objectId")
            XCTAssertNotNil(savedUser.sessionToken, "注册后应有 sessionToken")
            XCTAssertNotNil(savedUser.createdAt, "注册后应有 createdAt")
            XCTAssertEqual(BmobUser.current?.objectId, savedUser.objectId, "注册后应自动设置为 current user")

            // 清理：删除测试用户
            try? await deleteTestUser(savedUser)
        } catch let error as BmobError {
            XCTFail("注册失败: \(error.localizedDescription)")
        }
    }

    func testSignUpWithEmail() async throws {
        let user = BmobUser()
        user.username = testUsername
        user.password = testPassword
        user.email = "\(testUsername)@test.com"

        do {
            let savedUser = try await user.signUp()
            XCTAssertNotNil(savedUser.objectId)

            // 清理
            try? await deleteTestUser(savedUser)
        } catch let error as BmobError {
            XCTFail("注册失败: \(error.localizedDescription)")
        }
    }

    func testSignUpDuplicateUsername() async throws {
        let user = BmobUser()
        user.username = testUsername
        user.password = testPassword

        var savedUser: BmobUser?
        do {
            savedUser = try await user.signUp()
        } catch {
            XCTFail("首次注册应成功: \(error.localizedDescription)")
            return
        }

        // 尝试重复注册
        let duplicate = BmobUser()
        duplicate.username = user.username
        duplicate.password = testPassword

        do {
            _ = try await duplicate.signUp()
            XCTFail("重复用户名注册应失败")
        } catch let error as BmobError {
            // 预期失败
            XCTAssertTrue(error.code >= 100 || error.code == 9003 || error.code == 9002,
                          "应返回服务器错误码, 实际: \(error.code)")
        }

        // 清理
        if let savedUser = savedUser {
            try? await deleteTestUser(savedUser)
        }
    }

    // MARK: - Login Tests

    func testLoginWithUsernameAndPassword() async throws {
        // 先注册
        let username = testUsername
        let password = testPassword
        let user = BmobUser()
        user.username = username
        user.password = password
        var registered: BmobUser?
        do {
            registered = try await user.signUp()
        } catch {
            XCTFail("注册失败: \(error.localizedDescription)")
            return
        }

        BmobUser.logout()

        // 登录
        do {
            let loggedIn = try await BmobUser.login(username: username, password: password)
            XCTAssertNotNil(loggedIn.objectId)
            XCTAssertEqual(loggedIn.username, username)
            XCTAssertNotNil(loggedIn.sessionToken, "登录后应有 sessionToken")
            XCTAssertEqual(BmobUser.current?.objectId, loggedIn.objectId)
        } catch let error as BmobError {
            XCTFail("登录失败: \(error.localizedDescription)")
        }

        // 清理
        if let registered = registered {
            try? await deleteTestUser(registered)
        }
    }

    func testLoginWithWrongPassword() async throws {
        // 先注册
        let username = testUsername
        let password = testPassword
        let user = BmobUser()
        user.username = username
        user.password = password
        var registered: BmobUser?
        do {
            registered = try await user.signUp()
        } catch {
            XCTFail("注册失败: \(error.localizedDescription)")
            return
        }
        BmobUser.logout()

        // 用错误密码登录
        do {
            _ = try await BmobUser.login(username: username, password: "wrong_password")
            XCTFail("错误密码应登录失败")
        } catch let error as BmobError {
            // 预期失败
            XCTAssertTrue(error.code != 0, "应返回错误码")
        }

        // 清理
        if let registered = registered {
            try? await deleteTestUser(registered)
        }
    }

    func testLoginWithGenericAccount() async throws {
        // 先注册
        let username = testUsername
        let password = testPassword
        let user = BmobUser()
        user.username = username
        user.password = password
        var registered: BmobUser?
        do {
            registered = try await user.signUp()
        } catch {
            XCTFail("注册失败: \(error.localizedDescription)")
            return
        }
        BmobUser.logout()

        // 用通用账号登录（用户名方式）
        do {
            let loggedIn = try await BmobUser.login(account: username, password: password)
            XCTAssertNotNil(loggedIn.objectId)
        } catch let error as BmobError {
            XCTFail("通用账号登录失败: \(error.localizedDescription)")
        }

        // 清理
        if let registered = registered {
            try? await deleteTestUser(registered)
        }
    }

    // MARK: - Logout Tests

    func testLogoutClearsCurrentUser() async throws {
        let user = BmobUser()
        user.username = testUsername
        user.password = testPassword

        var registered: BmobUser?
        do {
            registered = try await user.signUp()
            XCTAssertNotNil(BmobUser.current)
        } catch {
            XCTFail("注册失败: \(error.localizedDescription)")
            return
        }

        BmobUser.logout()
        XCTAssertNil(BmobUser.current, "登出后 current 应为 nil")

        // 清理
        if let registered = registered {
            try? await deleteTestUser(registered)
        }
    }

    // MARK: - Password Management Tests

    func testUpdatePassword() async throws {
        // 注册
        let username = testUsername
        let password = testPassword
        let user = BmobUser()
        user.username = username
        user.password = password
        var registered: BmobUser?
        do {
            registered = try await user.signUp()
        } catch {
            XCTFail("注册失败: \(error.localizedDescription)")
            return
        }

        // 修改密码
        let newPassword = "new_password_456"
        do {
            try await registered?.updatePassword(oldPassword: password, newPassword: newPassword)

            // 验证：登出后用新密码登录
            BmobUser.logout()
            let loggedIn = try await BmobUser.login(username: username, password: newPassword)
            XCTAssertNotNil(loggedIn.objectId)
        } catch let error as BmobError {
            XCTFail("密码修改或验证失败: \(error.localizedDescription)")
        }

        // 清理
        if let registered = registered {
            try? await deleteTestUser(registered)
        }
    }

    // MARK: - Current User Persistence

    func testCurrentUserPersistence() async throws {
        let user = BmobUser()
        user.username = testUsername
        user.password = testPassword
        var registered: BmobUser?
        do {
            registered = try await user.signUp()
        } catch {
            XCTFail("注册失败: \(error.localizedDescription)")
            return
        }

        // 验证持久化：signUp 后已自动保存到 UserDefaults
        // 不先 logout，直接 restoreCurrent 验证持久化数据
        BmobUser.restoreCurrent()
        XCTAssertNotNil(BmobUser.current, "restoreCurrent 应恢复已持久化用户")
        XCTAssertEqual(BmobUser.current?.objectId, registered?.objectId)

        // 清理
        BmobUser.logout()
        if let registered = registered {
            try? await deleteTestUser(registered)
        }
    }

    // MARK: - User Info Update

    func testUpdateUserInfo() async throws {
        let user = BmobUser()
        user.username = testUsername
        user.password = testPassword
        var registered: BmobUser?
        do {
            registered = try await user.signUp()
        } catch {
            XCTFail("注册失败: \(error.localizedDescription)")
            return
        }

        // 更新邮箱
        registered?.email = "updated_\(testUsername)@test.com"
        do {
            try await registered?.update()
        } catch let error as BmobError {
            XCTFail("更新用户信息失败: \(error.localizedDescription)")
        }

        // 清理
        if let registered = registered {
            try? await deleteTestUser(registered)
        }
    }

    // MARK: - Yoyo-English AppKey Test

    func testInitWithYoyoEnglishAppKey() async throws {
        let yoyoAppKey = "ccc35082b04ea89ec1bfb1ca21a35bee"
        await BmobManager.shared.reset()
        do {
            try await Bmob.initialize(appKey: yoyoAppKey)
            print("✅ Yoyo-English init SUCCESS with appKey: \(yoyoAppKey)")
        } catch {
            print("❌ Yoyo-English init FAILED: \(error.localizedDescription)")
            XCTFail("Yoyo-English appKey 初始化失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// 删除测试用户
    private func deleteTestUser(_ user: BmobUser) async throws {
        guard let objectId = user.objectId else { return }
        try? await user.delete()
    }
}

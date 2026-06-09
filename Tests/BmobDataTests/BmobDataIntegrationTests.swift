import XCTest
@testable import BmobData
@testable import BmobCore

/// BmobData 集成测试 —— 真实 CRUD 操作
/// 测试密钥: 89e65e889367ea647974b90f3338b06d
/// 操作表: SwiftSDKTest（测试专用表）
///
/// 运行方式:
///   swift test --filter BmobDataIntegrationTests
///   或在 Xcode 中 Cmd+U
final class BmobDataIntegrationTests: XCTestCase {

    // MARK: - Test Key

    private let testAppKey = "89e65e889367ea647974b90f3338b06d"
    private let testClassName = "SwiftSDKTest"

    // 记录本次测试创建的对象 ID，tearDown 时批量清理
    private var createdObjectIds: [String] = []

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
        // 清理本次创建的所有测试数据
        // for objectId in createdObjectIds {
        //     let obj = BmobObject(className: testClassName)
        //     obj.objectId = objectId
        //     try? await obj.delete()
        // }
        // createdObjectIds.removeAll()

        // await BmobManager.shared.reset()
        // try await super.tearDown()
    }

    // MARK: - Helper

    /// 创建测试对象并追踪其 objectId
    private func createTestObject(_ fields: [String: Any]) async throws -> BmobObject {
        let obj = BmobObject(className: testClassName)
        for (key, value) in fields {
            obj[key] = value
        }
        let saved = try await obj.save()
        if let oid = saved.objectId {
            createdObjectIds.append(oid)
        }
        return saved
    }

    // MARK: - CRUD: Create (保存)

    func testSaveObject() async throws {
        let obj = try await createTestObject([
            "title": "Integration Test",
            "score": 100,
            "active": true
        ])

        XCTAssertNotNil(obj.objectId, "保存后应有 objectId")
        XCTAssertNotNil(obj.createdAt, "保存后应有 createdAt")
        if let oid = obj.objectId, let ca = obj.createdAt {
            print("✅ 创建成功: objectId=\(oid), createdAt=\(ca)")
        }
    }

    func testSaveMultipleObjects() async throws {
        for i in 0..<3 {
            let obj = try await createTestObject([
                "title": "Batch Item \(i)",
                "index": i,
                "created": Int(Date().timeIntervalSince1970)
            ])
            XCTAssertNotNil(obj.objectId)
        }
        print("✅ 批量创建 3 条成功")
    }

    // MARK: - CRUD: Read (查询)

    func testGetObjectById() async throws {
        // 先创建
        let saved = try await createTestObject(["title": "Read Test", "value": 42])

        // 再按 ID 查询
        guard let oid = saved.objectId else {
            XCTFail("应有 objectId")
            return
        }

        let query = BmobQuery(className: testClassName)
        let fetched = try await query.get(objectId: oid)

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.objectId, oid)
        XCTAssertEqual(fetched?["title"] as? String, "Read Test")
        XCTAssertEqual(fetched?["value"] as? Int, 42)
        print("✅ 按 ID 查询成功: objectId=\(oid)")
    }

    func testFindWithWhereClause() async throws {
        // 创建两条数据，用不同 title
        try await createTestObject(["title": "FindMe", "score": 10])
        try await createTestObject(["title": "IgnoreMe", "score": 20])

        // 查询 title == "FindMe"
        let results = try await BmobQuery(className: testClassName)
            .whereKey("title", equalTo: "FindMe")
            .find()

        XCTAssertFalse(results.isEmpty, "应至少找到一条 FindMe 数据")
        for obj in results {
            XCTAssertEqual(obj["title"] as? String, "FindMe")
        }
        print("✅ 条件查询成功，找到 \(results.count) 条")
    }

    func testFindWithComparison() async throws {
        try await createTestObject(["title": "High", "score": 100])
        try await createTestObject(["title": "Low", "score": 10])

        let results = try await BmobQuery(className: testClassName)
            .whereKey("score", greaterThan: 50)
            .find()

        XCTAssertFalse(results.isEmpty, "应找到 score > 50 的数据")
        for obj in results {
            if let score = obj["score"] as? Int {
                XCTAssertGreaterThan(score, 50)
            }
        }
        print("✅ 比较查询成功，找到 \(results.count) 条")
    }

    func testFindWithContainedIn() async throws {
        try await createTestObject(["title": "Cat_A", "tag": "red"])
        try await createTestObject(["title": "Cat_B", "tag": "blue"])
        try await createTestObject(["title": "Cat_C", "tag": "green"])

        let results = try await BmobQuery(className: testClassName)
            .whereKey("tag", containedIn: ["red", "blue"])
            .find()

        for obj in results {
            if let tag = obj["tag"] as? String {
                XCTAssertTrue(["red", "blue"].contains(tag))
            }
        }
        print("✅ containedIn 查询成功，找到 \(results.count) 条")
    }

    func testFindWithSorting() async throws {
        try await createTestObject(["title": "SortTest", "rank": 3])
        try await createTestObject(["title": "SortTest", "rank": 1])
        try await createTestObject(["title": "SortTest", "rank": 2])

        let results = try await BmobQuery(className: testClassName)
            .whereKey("title", equalTo: "SortTest")
            .order(byAscending: "rank")
            .find()

        // 验证升序
        var prevRank = Int.min
        for obj in results {
            if let rank = obj["rank"] as? Int {
                XCTAssertGreaterThanOrEqual(rank, prevRank)
                prevRank = rank
            }
        }
        print("✅ 排序查询成功，找到 \(results.count) 条")
    }

    func testFindWithPagination() async throws {
        for i in 0..<5 {
            try await createTestObject(["title": "PageTest", "index": i])
        }

        let page1 = try await BmobQuery(className: testClassName)
            .whereKey("title", equalTo: "PageTest")
            .limit(2)
            .skip(0)
            .order(byAscending: "index")
            .find()

        let page2 = try await BmobQuery(className: testClassName)
            .whereKey("title", equalTo: "PageTest")
            .limit(2)
            .skip(2)
            .order(byAscending: "index")
            .find()

        XCTAssertEqual(page1.count, 2, "第一页应有 2 条")
        XCTAssertGreaterThanOrEqual(page2.count, 1, "第二页至少有 1 条")

        // 验证两页不重复
        let page1Ids = Set(page1.compactMap { $0.objectId })
        let page2Ids = Set(page2.compactMap { $0.objectId })
        XCTAssertTrue(page1Ids.intersection(page2Ids).isEmpty, "两页不应有重复")
        print("✅ 分页查询成功: page1=\(page1.count), page2=\(page2.count)")
    }

    func testSelectKeys() async throws {
        try await createTestObject(["title": "SelectMe", "content": "Hidden", "note": "AlsoHidden"])

        let results = try await BmobQuery(className: testClassName)
            .whereKey("title", equalTo: "SelectMe")
            .selectKeys(["title"])
            .find()

        if let obj = results.first {
            XCTAssertEqual(obj["title"] as? String, "SelectMe")
            // selectKeys 指定只返回 title，content/note 可能不存在
            print("✅ selectKeys 查询成功")
        }
    }

    // MARK: - CRUD: Count (计数)

    func testCount() async throws {
        // 先确保有数据
        try await createTestObject(["title": "CountTest", "val": 1])
        try await createTestObject(["title": "CountTest", "val": 2])

        let count = try await BmobQuery(className: testClassName)
            .whereKey("title", equalTo: "CountTest")
            .count()

        XCTAssertGreaterThanOrEqual(count, 2, "至少应有 2 条 CountTest 数据")
        print("✅ 计数查询成功: count=\(count)")
    }

    // MARK: - CRUD: Update (更新)

    func testUpdateObject() async throws {
        let saved = try await createTestObject(["title": "Original", "version": 1])

        guard let oid = saved.objectId else {
            XCTFail("应有 objectId")
            return
        }

        // 修改字段
        saved["title"] = "Updated"
        saved["version"] = 2
        let updated = try await saved.update()

        XCTAssertEqual(updated["title"] as? String, "Updated")
        XCTAssertEqual(updated["version"] as? Int, 2)

        // 二次确认：重新查询
        let refetched = try await BmobQuery(className: testClassName).get(objectId: oid)
        XCTAssertEqual(refetched?["title"] as? String, "Updated")
        print("✅ 更新成功: objectId=\(oid), title=Updated")
    }

    func testAtomicIncrement() async throws {
        let saved = try await createTestObject(["title": "CounterTest", "views": 0])

        guard let oid = saved.objectId else {
            XCTFail("应有 objectId")
            return
        }

        // 原子递增
        saved.incrementKey("views", by: 5)
        let updated = try await saved.update()

        // 注意: incrementKey 会在 data 中设置 BmobIncrement，
        // update 后服务器会返回新的值
        print("✅ 原子递增成功: objectId=\(oid)")

        // 验证服务器端值已更新
        let refetched = try await BmobQuery(className: testClassName).get(objectId: oid)
        if let views = refetched?["views"] as? Int {
            XCTAssertEqual(views, 5, "views 应为 5")
            print("✅ 验证原子递增: views=\(views)")
        }
    }

    // MARK: - CRUD: Delete (删除)

    func testDeleteObject() async throws {
        let saved = try await createTestObject(["title": "ToDelete"])
        XCTAssertNotNil(saved.objectId)

        guard let oid = saved.objectId else {
            XCTFail("应有 objectId")
            return
        }

        // 从追踪列表移除（手动验证删除）
        createdObjectIds.removeAll { $0 == oid }

        try await saved.delete()

        // 二次确认：重新查询应为空
        let refetched = try await BmobQuery(className: testClassName).get(objectId: oid)
        XCTAssertNil(refetched, "删除后查询应为 nil")
        print("✅ 删除成功: objectId=\(oid)")
    }

    // MARK: - BQL 查询

    func testBQLQuery() async throws {
        try await createTestObject(["title": "BQLTest", "score": 999])

        let results = try await BmobQuery.query(
            bql: "select * from \(testClassName) where title='BQLTest'"
        )
        XCTAssertFalse(results.isEmpty, "BQL 查询应找到数据")
        print("✅ BQL 查询成功，找到 \(results.count) 条")
    }

    func testBQLCount() async throws {
        try await createTestObject(["title": "BQLCountTest", "val": 1])
        try await createTestObject(["title": "BQLCountTest", "val": 2])

        let stats = try await BmobQuery.statistics(
            bql: "select count(*) from \(testClassName) where title='BQLCountTest'"
        )
        XCTAssertFalse(stats.isEmpty, "BQL 统计应有结果")
        print("✅ BQL 统计成功: \(stats)")
    }

    // MARK: - 批量操作

    func testBatchCreate() async throws {
        let batch = BmobBatch()
        for i in 0..<3 {
            let obj = BmobObject(className: testClassName)
            obj["title"] = "BatchCreate_\(i)"
            batch.create(obj)
        }

        let results = try await batch.execute()
        XCTAssertEqual(results.count, 3, "应有 3 个结果")

        // 记录 objectId 以便清理
        for result in results {
            if case .success(let data) = result, let oid = data["objectId"] as? String {
                createdObjectIds.append(oid)
            }
        }

        let successCount = results.filter { $0.isSuccess }.count
        XCTAssertEqual(successCount, 3, "3 条应全部成功")
        print("✅ 批量创建成功: success=\(successCount)")
    }

    // MARK: - 地理位置查询

    func testGeoPointNear() async throws {
        let pt = BmobGeoPoint(latitude: 22.5431, longitude: 114.0579) // 深圳

        try await createTestObject([
            "title": "Shenzhen",
            "location": BmobGeoPoint(latitude: 22.5431, longitude: 114.0579)
        ])
        try await createTestObject([
            "title": "Beijing",
            "location": BmobGeoPoint(latitude: 39.9042, longitude: 116.4074)
        ])

        let results = try await BmobQuery(className: testClassName)
            .whereKey("location", nearGeoPoint: pt, withinKilometers: 100)
            .find()

        // 深圳应在 100km 内，北京不在
        let titles = results.compactMap { $0["title"] as? String }
        XCTAssertTrue(titles.contains("Shenzhen"), "深圳应在范围内")
        XCTAssertFalse(titles.contains("Beijing"), "北京不应在范围内")
        print("✅ 地理位置查询成功，找到 \(results.count) 条")
    }

    // MARK: - 错误处理测试

    func testGetNonExistentObject() async throws {
        let result = try await BmobQuery(className: testClassName)
            .get(objectId: "NonExistentId123")
        XCTAssertNil(result, "不存在的 ID 应返回 nil")
        print("✅ 查询不存在对象返回 nil")
    }

    func testDeleteWithoutObjectId() async throws {
        let obj = BmobObject(className: testClassName)
        obj["title"] = "NoID"

        do {
            try await obj.delete()
            XCTFail("无 objectId 删除应失败")
        } catch let error as BmobError {
            XCTAssertEqual(error.code, 9008, "应为 invalidParameter 错误")
            print("✅ 无 objectId 删除正确抛出错误: \(error.code)")
        }
    }

    func testUpdateWithoutObjectId() async throws {
        let obj = BmobObject(className: testClassName)
        obj["title"] = "NoID"

        do {
            _ = try await obj.update()
            XCTFail("无 objectId 更新应失败")
        } catch let error as BmobError {
            XCTAssertEqual(error.code, 9008, "应为 invalidParameter 错误")
            print("✅ 无 objectId 更新正确抛出错误: \(error.code)")
        }
    }
}

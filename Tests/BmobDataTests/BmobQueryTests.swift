import XCTest
@testable import BmobData

final class BmobQueryTests: XCTestCase {

    func testBmobQueryCreation() {
        let query = BmobQuery(className: "TestTable")
        XCTAssertEqual(query.className, "TestTable")
        XCTAssertEqual(query.limit, 100)
        XCTAssertEqual(query.skip, 0)
    }

    func testWhereEqualTo() {
        let query = BmobQuery(className: "Note")
            .whereKey("status", equalTo: 1)
        XCTAssertNotNil(query)
    }

    func testWhereNotEqualTo() {
        let query = BmobQuery(className: "Note")
            .whereKey("status", notEqualTo: 0)
        XCTAssertNotNil(query)
    }

    func testComparisonOperators() {
        let query = BmobQuery(className: "Score")
            .whereKey("points", greaterThan: 100)
            .whereKey("points", lessThan: 200)

        XCTAssertNotNil(query)
    }

    func testContainedIn() {
        let query = BmobQuery(className: "Note")
            .whereKey("category", containedIn: ["A", "B", "C"])

        XCTAssertNotNil(query)
    }

    func testNotContainedIn() {
        let query = BmobQuery(className: "Note")
            .whereKey("category", notContainedIn: ["D", "E"])

        XCTAssertNotNil(query)
    }

    func testExistsQueries() {
        let query = BmobQuery(className: "Note")
            .whereKeyExists("email")
        XCTAssertNotNil(query)
    }

    func testDoesNotExistQueries() {
        let query = BmobQuery(className: "Note")
            .whereKeyDoesNotExist("deletedAt")
        XCTAssertNotNil(query)
    }

    func testRegexQueries() {
        let query = BmobQuery(className: "Note")
            .whereKey("title", matchesRegex: "^Hello")
            .whereKey("title", startsWith: "Hello")
            .whereKey("title", endsWith: "World")
        XCTAssertNotNil(query)
    }

    func testCompoundQueries() {
        let q1 = BmobQuery(className: "Note").whereKey("status", equalTo: 1)
        let q2 = BmobQuery(className: "Note").whereKey("level", greaterThan: 5)

        let andQuery = BmobQuery.and([q1, q2])
        let orQuery = BmobQuery.or([q1, q2])

        XCTAssertNotNil(andQuery)
        XCTAssertNotNil(orQuery)
    }

    func testSorting() {
        let query = BmobQuery(className: "Note")
            .order(byAscending: "createdAt")
            .order(byDescending: "level")

        XCTAssertNotNil(query)
    }

    func testPagination() {
        let query = BmobQuery(className: "Note")
            .limit(20)
            .skip(40)

        XCTAssertEqual(query.limit, 20)
        XCTAssertEqual(query.skip, 40)
    }

    func testSelectKeys() {
        let query = BmobQuery(className: "Note")
            .selectKeys(["title", "content", "createdAt"])
        XCTAssertNotNil(query)
    }

    func testIncludeKey() {
        let query = BmobQuery(className: "Note")
            .includeKey("author")
            .includeKey("author.company")

        XCTAssertNotNil(query)
    }

    func testStatistics() {
        let query = BmobQuery(className: "Score")
            .statistics()
            .groupBy(["category"])
        XCTAssertNotNil(query)
    }

    func testGeoQuery() {
        let point = BmobGeoPoint(latitude: 22.5, longitude: 113.9)
        let query = BmobQuery(className: "Place")
            .whereKey("location", nearGeoPoint: point)
            .whereKey("location", nearGeoPoint: point, withinKilometers: 10)
            .whereKey("location", nearGeoPoint: point, withinMiles: 5)
            .whereKey("location", nearGeoPoint: point, withinRadians: 0.1)

        XCTAssertNotNil(query)
    }

    func testGeoBoxQuery() {
        let sw = BmobGeoPoint(latitude: 22.0, longitude: 113.0)
        let ne = BmobGeoPoint(latitude: 23.0, longitude: 114.0)
        let query = BmobQuery(className: "Place")
            .whereKey("location", withinGeoBox: sw, northeast: ne)

        XCTAssertNotNil(query)
    }

    func testCachePolicy() {
        let query = BmobQuery(className: "Note")
        query.cachePolicy = .cacheOnly

        XCTAssertEqual(query.cachePolicy, .cacheOnly)
    }
}

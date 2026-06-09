import XCTest
@testable import BmobData

final class BmobObjectTests: XCTestCase {

    func testBmobObjectCreation() {
        let obj = BmobObject(className: "TestTable")
        XCTAssertEqual(obj.className, "TestTable")
        XCTAssertNil(obj.objectId)
    }

    func testBmobObjectKeyValueAccess() {
        let obj = BmobObject(className: "Note")
        obj["title"] = "Hello"
        obj["count"] = 42

        XCTAssertEqual(obj["title"] as? String, "Hello")
        XCTAssertEqual(obj["count"] as? Int, 42)
    }

    func testBmobObjectInitWithData() {
        let data: [String: Any] = [
            "objectId": "abc123",
            "createdAt": "2025-01-01 12:00:00",
            "title": "Test"
        ]
        let obj = BmobObject(className: "Note", data: data)
        XCTAssertEqual(obj.objectId, "abc123")
        XCTAssertEqual(obj["title"] as? String, "Test")
    }

    func testBmobObjectFullData() {
        let obj = BmobObject(className: "Note")
        obj["title"] = "Hello"
        let full = obj.fullData
        XCTAssertEqual(full["title"] as? String, "Hello")
    }

    func testBmobGeoPoint() {
        let point = BmobGeoPoint(latitude: 22.5, longitude: 113.9)
        let dict = point.dictionary

        XCTAssertEqual(dict["__type"] as? String, "GeoPoint")
        XCTAssertEqual(dict["latitude"] as? Double, 22.5)
        XCTAssertEqual(dict["longitude"] as? Double, 113.9)
    }

    func testBmobPointer() {
        let obj = BmobObject(className: "Author")
        obj["name"] = "Test"

        let pointer = BmobPointer(className: "Author", objectId: "abc")
        let dict = pointer.dictionary

        XCTAssertEqual(dict["__type"] as? String, "Pointer")
        XCTAssertEqual(dict["className"] as? String, "Author")
        XCTAssertEqual(dict["objectId"] as? String, "abc")
    }

    func testIncrementCounter() {
        let obj = BmobObject(className: "Counter")
        obj.incrementKey("views", by: 5)

        let increment = obj["views"] as? BmobIncrement
        XCTAssertNotNil(increment)
        XCTAssertEqual(increment?.amount, 5)
    }

    func testDecrementCounter() {
        let obj = BmobObject(className: "Counter")
        obj.decrementKey("stock", by: 2)

        let increment = obj["stock"] as? BmobIncrement
        XCTAssertNotNil(increment)
        XCTAssertEqual(increment?.amount, -2)
    }
}

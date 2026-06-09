import Foundation
import BmobCore

// MARK: - BmobGeoPoint

/// 地理位置坐标
public struct BmobGeoPoint: Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// 序列化为 Bmob GeoPoint JSON
    var dictionary: [String: Any] {
        [
            "__type": "GeoPoint",
            "latitude": latitude,
            "longitude": longitude
        ]
    }

    /// 从字典反序列化
    static func from(dictionary: [String: Any]) -> BmobGeoPoint? {
        guard let type = dictionary["__type"] as? String,
              type == "GeoPoint",
              let lat = dictionary["latitude"] as? Double,
              let lng = dictionary["longitude"] as? Double else {
            return nil
        }
        return BmobGeoPoint(latitude: lat, longitude: lng)
    }
}

// MARK: - BmobSerializer

/// 数据序列化器：将 Swift 原生类型转换为 Bmob 后端 JSON 格式
public enum BmobSerializer {

    /// 序列化数据字典
    public static func serialize(_ data: [String: Any]) throws -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in data {
            result[key] = try serializeValue(value)
        }
        return result
    }

    /// 序列化单个值
    public static func serializeValue(_ value: Any) throws -> Any {
        switch value {
        case let str as String:
            return str
        case let num as Int:
            return num
        case let num as Int64:
            return num
        case let num as Double:
            return num
        case let num as Float:
            return Double(num)
        case let num as NSNumber:
            return num
        case let bool as Bool:
            return bool
        case let date as Date:
            return [
                "__type": "Date",
                "iso": BmobDateFormatter.string(from: date)
            ]
        case let pointer as BmobPointer:
            return pointer.dictionary
        case let geoPoint as BmobGeoPoint:
            return geoPoint.dictionary
        case let increment as BmobIncrement:
            return increment.dictionary
        case let file as BmobDataFile:
            return file.dictionary
        case let relation as BmobRelationData:
            return relation.dictionary
        case let array as [Any]:
            return try array.map { try serializeValue($0) }
        case let dict as [String: Any]:
            return try serialize(dict)
        case let data as Data:
            // Data 类型：暂不支持直接上传，需先转为 BmobFile
            return data.base64EncodedString()
        case is NSNull:
            return NSNull()
        default:
            // 尝试将自定义对象转为字符串
            return String(describing: value)
        }
    }

    /// 反序列化响应数据
    public static func deserialize(_ data: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in data {
            result[key] = deserializeValue(value)
        }
        return result
    }

    /// 反序列化单个值
    static func deserializeValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            // 检查 __type
            if let type = dict["__type"] as? String {
                switch type {
                case "Date":
                    if let dateStr = dict["iso"] as? String {
                        return BmobDateFormatter.date(from: dateStr) ?? value
                    }
                case "Pointer":
                    if let className = dict["className"] as? String,
                       let objectId = dict["objectId"] as? String {
                        return BmobPointer(className: className, objectId: objectId)
                    }
                case "GeoPoint":
                    if let gp = BmobGeoPoint.from(dictionary: dict) {
                        return gp
                    }
                case "File":
                    return dict
                case "Relation":
                    return dict
                default:
                    break
                }
            }
            // 递归反序列化子字典
            return deserialize(dict)
        } else if let array = value as? [Any] {
            return array.map { deserializeValue($0) }
        }
        return value
    }
}

// MARK: - BmobDataFile (Internal)

/// 文件类型占位（用于 BmobObject 数据中的 File 类型字段）
struct BmobDataFile: Sendable {
    let url: String
    let filename: String?

    init(url: String, filename: String? = nil) {
        self.url = url
        self.filename = filename
    }

    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "__type": "File",
            "url": url
        ]
        if let filename = filename {
            dict["filename"] = filename
        }
        return dict
    }
}

// MARK: - BmobRelationData (Internal)

/// 关联关系类型
struct BmobRelationData: Sendable {
    let className: String

    var dictionary: [String: Any] {
        [
            "__type": "Relation",
            "className": className
        ]
    }
}

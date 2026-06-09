import Foundation
import BmobCore

// MARK: - BmobACL

/// Bmob 访问控制列表
///
/// ```swift
/// let acl = BmobACL()
/// acl.setPublicReadAccess(true)
/// acl.setReadAccess(for: userId)
/// note["ACL"] = acl
/// ```
public class BmobACL: @unchecked Sendable {

    /// 公共读权限
    public var publicReadAccess: Bool = false {
        didSet { setAsterisk(key: "read", value: publicReadAccess) }
    }

    /// 公共写权限
    public var publicWriteAccess: Bool = false {
        didSet { setAsterisk(key: "write", value: publicWriteAccess) }
    }

    /// 内部权限字典: { "userId": { "read": true, "write": false } }
    private var permissions: [String: [String: Bool]] = [:]

    public init() {}

    // MARK: - Public Access

    /// 设置公共读权限
    public func setPublicReadAccess(_ allowed: Bool) {
        publicReadAccess = allowed
    }

    /// 设置公共写权限
    public func setPublicWriteAccess(_ allowed: Bool) {
        publicWriteAccess = allowed
    }

    // MARK: - User Access

    /// 设置用户读权限
    public func setReadAccess(for userId: String) {
        var userPerms = permissions[userId] ?? [:]
        userPerms["read"] = true
        permissions[userId] = userPerms
    }

    /// 设置用户写权限
    public func setWriteAccess(for userId: String) {
        var userPerms = permissions[userId] ?? [:]
        userPerms["write"] = true
        permissions[userId] = userPerms
    }

    /// 设置用户读+写权限
    public func setReadWriteAccess(for userId: String) {
        permissions[userId] = ["read": true, "write": true]
    }

    /// 移除所有读权限
    public func setUnReadAccess(for userId: String) {
        var userPerms = permissions[userId] ?? [:]
        userPerms["read"] = false
        permissions[userId] = userPerms
    }

    /// 移除所有写权限
    public func setUnWriteAccess(for userId: String) {
        var userPerms = permissions[userId] ?? [:]
        userPerms["write"] = false
        permissions[userId] = userPerms
    }

    // MARK: - Role Access

    /// 设置角色读权限
    public func setReadAccess(for role: BmobRole) {
        let roleName = role.roleName ?? "role:\(role.objectId ?? "")"
        setReadAccess(for: "role:\(roleName)")
    }

    /// 设置角色写权限
    public func setWriteAccess(for role: BmobRole) {
        let roleName = role.roleName ?? "role:\(role.objectId ?? "")"
        setWriteAccess(for: "role:\(roleName)")
    }

    // MARK: - Serialization

    /// 转换为后端 JSON 格式
    var aclDictionary: [String: Any] {
        var dict: [String: Any] = permissions
        if let asterisk = asteriskPermissions, !asterisk.isEmpty {
            dict["*"] = asterisk
        }
        return dict
    }

    /// 从 JSON 反序列化
    static func from(dictionary: [String: Any]) -> BmobACL {
        let acl = BmobACL()
        for (key, value) in dictionary {
            if key == "*", let perms = value as? [String: Bool] {
                acl.publicReadAccess = perms["read"] ?? false
                acl.publicWriteAccess = perms["write"] ?? false
            } else if let perms = value as? [String: Bool] {
                acl.permissions[key] = perms
            }
        }
        return acl
    }

    // MARK: - Private

    private var asteriskPermissions: [String: Bool]? {
        var perms: [String: Bool] = [:]
        if publicReadAccess { perms["read"] = true }
        if publicWriteAccess { perms["write"] = true }
        return perms.isEmpty ? nil : perms
    }

    private func setAsterisk(key: String, value: Bool) {
        if value {
            var userPerms = permissions["*"] ?? [:]
            userPerms[key] = true
            permissions["*"] = userPerms
        } else {
            var userPerms = permissions["*"] ?? [:]
            userPerms.removeValue(forKey: key)
            if userPerms.isEmpty {
                permissions.removeValue(forKey: "*")
            } else {
                permissions["*"] = userPerms
            }
        }
    }
}

// MARK: - BmobRole

/// Bmob 角色
/// 继承自 BmobObject，通过 BmobRelation 管理角色成员
///
/// ```swift
/// let role = BmobRole(name: "Admin")
/// role.users.add(user)
/// try await role.save()
/// ```
open class BmobRole: BmobObject {

    /// 角色名称
    open var roleName: String? {
        get { self["name"] as? String }
        set { self["name"] = newValue }
    }

    /// 角色关联的用户
    open var users: BmobRelation

    /// 角色关联的子角色
    open var roles: BmobRelation

    /// 初始化
    public init(name: String) {
        self.users = BmobRelation()
        self.roles = BmobRelation()
        super.init(className: "_Role")
        self.roleName = name
    }

    required public init(className: String, data: [String: Any]) {
        self.users = BmobRelation()
        self.roles = BmobRelation()
        super.init(className: className, data: data)
    }

    /// 保存角色
    @discardableResult
    open override func save() async throws -> BmobObject {
        // 序列化 users 和 roles 关联
        if !users.isEmpty {
            self["users"] = users
        }
        if !roles.isEmpty {
            self["roles"] = roles
        }
        return try await super.save()
    }

    /// 更新角色
    @discardableResult
    open override func update() async throws -> BmobObject {
        if !users.isEmpty {
            self["users"] = users
        }
        if !roles.isEmpty {
            self["roles"] = roles
        }
        return try await super.update()
    }
}

// MARK: - BmobRelation

/// Bmob 关联关系
/// 用于管理一对多/多对多关系
///
/// ```swift
/// let relation = BmobRelation()
/// relation.add(user)
/// post["likes"] = relation
/// ```
public class BmobRelation: @unchecked Sendable {

    /// 添加操作列表
    private var addObjects: [BmobObject] = []

    /// 移除操作列表
    private var removeObjects: [BmobObject] = []

    /// 是否为空
    public var isEmpty: Bool {
        addObjects.isEmpty && removeObjects.isEmpty
    }

    public init() {}

    /// 添加关联对象
    public func add(_ object: BmobObject) {
        addObjects.append(object)
    }

    /// 移除关联对象
    public func remove(_ object: BmobObject) {
        removeObjects.append(object)
    }

    /// 序列化为后端 JSON
    var dictionary: [String: Any] {
        var dict: [String: Any] = [:]

        if !addObjects.isEmpty {
            dict["__op"] = "AddRelation"
            dict["objects"] = addObjects.compactMap { obj -> [String: Any]? in
                guard let objectId = obj.objectId else { return nil }
                return [
                    "__type": "Pointer",
                    "className": obj.className,
                    "objectId": objectId
                ]
            }
        }

        if !removeObjects.isEmpty {
            dict["__op"] = "RemoveRelation"
            dict["objects"] = removeObjects.compactMap { obj -> [String: Any]? in
                guard let objectId = obj.objectId else { return nil }
                return [
                    "__type": "Pointer",
                    "className": obj.className,
                    "objectId": objectId
                ]
            }
        }

        return dict
    }
}

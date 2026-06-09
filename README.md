# BmobSwiftSDK

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2015%2B%20%7C%20macOS%2012%2B-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![CocoaPods](https://img.shields.io/badge/CocoaPods-v1.0.0-red.svg)](https://cocoapods.org/pods/BmobSwiftSDK)

BmobSwiftSDK 是 Bmob 后端云的全新纯 Swift SDK，专为 Swift 现代并发模型设计，提供简洁、高效的云端数据管理能力。

## 特性

- **纯 Swift 实现** - 无 Objective-C 桥接，完全适配 Swift 生态
- **async/await** - 原生支持 Swift Concurrency，告别回调地狱
- **模块化设计** - SPM/CocoaPods 按需集成（Core/Data/User/File/Cloud）
- **加密传输** - 端到端 AES-128-CBC 加密，安全可靠
- **类型安全** - BmobError 枚举 + throws 错误处理
- **完整查询** - 条件/模糊/地理/统计/BQL 等查询能力
- **实时数据** - WebSocket 连接 + AsyncStream 事件流

## 平台支持

| 平台 | 最低版本 |
|------|----------|
| iOS | 15.0+ |
| macOS | 12.0+ |

## 安装

### Swift Package Manager

在 Xcode 中，选择 `File > Add Package Dependencies`，输入：

```
https://github.com/bmob/BmobSwiftSDK
```

或直接在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/bmob/BmobSwiftSDK", from: "1.0.0")
]
```

### CocoaPods

在 `Podfile` 中添加：

```ruby
pod 'BmobSwiftSDK', '~> 1.0.0'
```

然后执行：

```bash
pod install
```

## 快速开始

### 1. 初始化

```swift
import BmobSDK

Bmob.initialize(appKey: "your-app-key")
```

### 2. 数据操作

```swift
// 创建对象
let gameScore = BmobObject(className: "GameScore")
gameScore["playerName"] = "Player1"
gameScore["score"] = 100

try await gameScore.save()

// 查询数据
let query = BmobQuery(className: "GameScore")
query.whereKey("playerName", equalTo: "Player1")
let results = try await query.find()

// 条件查询
let query = BmobQuery(className: "GameScore")
query.whereKey("score", greaterThan: 50)
query.order(byDescending: "score")
let topScores = try await query.find()
```

### 3. 用户认证

```swift
// 注册
let user = BmobUser()
user.username = "username"
user.password = "password"
try await user.signUp()

// 登录
let user = try await BmobUser.login(account: "username", password: "password")

// 退出登录
BmobUser.logout()
```

### 4. 文件上传

```swift
let file = BmobFile(localPath: "/path/to/image.jpg")
try await file.upload()
print("File URL: \(file.url ?? "")")
```

### 5. 云函数

```swift
// 调用云函数
let result = try await BmobCloud.run(function: "helloWorld", params: ["name": "Bmob"])

// 类型安全调用
struct HelloResponse: Decodable {
    let message: String
}
let response: HelloResponse = try await BmobCloud.run(function: "helloWorld")
```

## 文档

完整文档请访问：[Bmob Swift SDK 文档](https://doc.bmobapp.com/data/swift/)

- [快速入门](https://doc.bmobapp.com/data/swift/quick-start/)
- [API 参考](https://doc.bmobapp.com/data/swift/api-reference/)
- [迁移指南](https://doc.bmobapp.com/data/swift/migration-guide/)

## 示例项目

coming soon...

## 版本历史

详见 [CHANGELOG](CHANGELOG.md)

## 开源协议

本项目基于 MIT 协议开源，详见 [LICENSE](LICENSE)

## 支持

- 官方文档：https://doc.bmobapp.com/data/swift/
- 官网：https://www.bmobapp.com
- 邮箱：support@bmob.cn

---

Made with ❤️ by [Bmob](https://www.bmobapp.com)

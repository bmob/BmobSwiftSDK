# BmobSwiftSDK

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2015%2B%20%7C%20macOS%2012%2B-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![CocoaPods](https://img.shields.io/badge/CocoaPods-v1.0.7-red.svg)](https://cocoapods.org/pods/BmobSwiftSDK)

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
    .package(url: "https://github.com/bmob/BmobSwiftSDK", from: "1.0.7")
]
```

### CocoaPods

在 `Podfile` 中添加：

```ruby
pod 'BmobSwiftSDK', '~> 1.0.7'
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
let file = BmobFile(filePath: "/path/to/image.jpg")
try await file?.upload()
print("File URL: \(file?.url ?? "")")
print("CDN: \(file?.cdn ?? "")")
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

## 实时数据监听

监听地址优先级：用户自定义地址 → 初始化响应的 `io` → `http://io.codenow.cn:3010`。
可在初始化前后设置；请用 `await` 保证设置完成后再连接：

```swift
try await Bmob.resetIODomain("https://realtime.example.com:443")
// try await Bmob.resetIODomain(nil) // 恢复使用服务端配置或默认地址
```

支持 `http://`、`https://`、`ws://`、`wss://` 及 `host:port`（默认 HTTP）。
地址只包含协议、主机和可选端口，SDK 自动拼接握手及 WebSocket 路径。
已经建立连接时，新地址在下次连接或自动重连时生效；需立即切换可先 `disconnect()` 再 `connect()`。
`disconnect()` 会结束现有事件流，切换后需重新获取 `eventStream()`。
API 请求域名仍通过 `Bmob.resetDomain` 独立设置。

初始化完成后，保留 `BmobEvent` 实例，登记订阅并连接：

```swift
let event = BmobEvent() // 存为属性，保持生命周期
try await Bmob.initialize(appKey: "YOUR_APP_KEY")
let messages = event.eventStream()
event.listenTableChange(className: "Note") // 表更新，包含表内数据变化
event.listenRowChange(.deleteRow, tableName: "Note", objectId: "row-id")
event.connect()

for await message in messages {
    print(message.action ?? "", message.className ?? "", message.data ?? [:])
}
```

支持 `.updateTable`、`.deleteTable`、`.updateRow`、`.deleteRow`，分别使用
`listenTableChange(_:tableName:)` 或 `listenRowChange(_:tableName:objectId:)`。
取消订阅使用对应的 `cancelListenTableChange` / `cancelListenRowChange` 方法。

也可设置 `BmobEventDelegate`；回调在主队列执行。`bmobEventDidConnect` 表示连接建立，
`bmobEventCanStartListen` 表示服务端允许订阅。连接前登记的订阅会在此时自动发送。
默认断线后每 5 秒重连并恢复有效订阅；可设置 `autoReconnect = false`。
`event.disconnect()` 停止连接和重连并结束所有事件流，保留订阅供下次连接使用。
重连期间事件流保持开启，但不会补发断线期间的变更；需要完整数据时请重新查询。

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
- 邮箱：magic@bmobcloud.com

---

Made with ❤️ by [Bmob](https://www.bmobapp.com)

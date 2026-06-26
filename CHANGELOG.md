# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.4] - 2026-06-26

### Fixed

- 修复 `saveCurrent()` 和 `restoreCurrent()` 中 `sessionToken` 写入 `BmobManager` 的竞态条件
- 将 `saveCurrent()` 和 `restoreCurrent()` 改为 `async` 方法，使用 `await` 替代 `Task { }` 确保 sessionToken 在方法返回前已写入
- 修复登录后立即发起查询时 sessionToken 为空的问题（`Task` 调度延迟导致 `buildRequestParams` 读到 nil）

## [1.0.3] - 2026-06-26

### Fixed

- 修复 `/8/find` 查询协议不传递 `sessionToken` 的问题，导致 ACL 保护的数据被过滤
- `BmobQuery`、`BmobObject`、`BmobBatch` 的请求参数补齐 `sessionToken`
- 在 `BmobManager` 中添加 `sessionToken` 公共属性作为跨模块身份缓存

## [1.0.1] - 2024-06-09

### Fixed

- Fix CocoaPods subspec module exports (@_exported import)
- Ensure proper module dependency chain for subspecs

## [1.0.0] - 2024-06-09

### Added

- Initial release of BmobSwiftSDK
- Full Swift implementation with async/await support
- Modular architecture (Core/Data/User/File/Cloud)
- AES-128-CBC encrypted communication
- Complete CRUD operations for data objects
- Advanced query system (conditions, geo, BQL, statistics)
- User authentication and management
- File upload with progress tracking
- Cloud functions with type-safe decoding
- ACL and Role-based access control
- WebSocket-based real-time data subscription
- Closure compatibility layer for existing code
- Support for Swift Package Manager and CocoaPods

### Modules

- **BmobCore**: Encryption, HTTP client, configuration management
- **BmobData**: Object CRUD, queries, batch operations, ACL
- **BmobUser**: Sign up, login, logout, third-party auth, SMS
- **BmobFile**: Upload, download, delete with progress
- **BmobCloud**: Cloud functions with generic decoding
- **BmobSDK**: Unified umbrella package

### Platforms

- iOS 15.0+
- macOS 12.0+

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BmobSwiftSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        // 伞式全量模块 — 一键集成
        .library(
            name: "BmobSDK",
            targets: ["BmobSDK"]
        ),
        // 按需子模块 — 减小包体积
        .library(
            name: "BmobCore",
            targets: ["BmobCore"]
        ),
        .library(
            name: "BmobData",
            targets: ["BmobData"]
        ),
        .library(
            name: "BmobUser",
            targets: ["BmobUser"]
        ),
        .library(
            name: "BmobFile",
            targets: ["BmobFile"]
        ),
        .library(
            name: "BmobCloud",
            targets: ["BmobCloud"]
        ),
    ],
    dependencies: [],
    targets: [
        // Core — 加密/网络/配置，无外部依赖
        .target(
            name: "BmobCore",
            dependencies: [],
            path: "Sources/BmobCore"
        ),
        .testTarget(
            name: "BmobCoreTests",
            dependencies: ["BmobCore"],
            path: "Tests/BmobCoreTests"
        ),

        // Data — 数据 CRUD + 查询，依赖 Core
        .target(
            name: "BmobData",
            dependencies: ["BmobCore"],
            path: "Sources/BmobData"
        ),
        .testTarget(
            name: "BmobDataTests",
            dependencies: ["BmobData"],
            path: "Tests/BmobDataTests"
        ),

        // User — 用户管理，依赖 Core + Data
        .target(
            name: "BmobUser",
            dependencies: ["BmobCore", "BmobData"],
            path: "Sources/BmobUser"
        ),
        .testTarget(
            name: "BmobUserTests",
            dependencies: ["BmobUser"],
            path: "Tests/BmobUserTests"
        ),

        // File — 文件管理，依赖 Core + Data
        .target(
            name: "BmobFile",
            dependencies: ["BmobCore", "BmobData"],
            path: "Sources/BmobFile"
        ),
        .testTarget(
            name: "BmobFileTests",
            dependencies: ["BmobFile"],
            path: "Tests/BmobFileTests"
        ),

        // Cloud — 云函数，依赖 Core
        .target(
            name: "BmobCloud",
            dependencies: ["BmobCore"],
            path: "Sources/BmobCloud"
        ),
        .testTarget(
            name: "BmobCloudTests",
            dependencies: ["BmobCloud"],
            path: "Tests/BmobCloudTests"
        ),

        // 伞式模块 — 依赖所有子模块，re-export
        .target(
            name: "BmobSDK",
            dependencies: [
                "BmobCore",
                "BmobData",
                "BmobUser",
                "BmobFile",
                "BmobCloud",
            ],
            path: "Sources/BmobSDK"
        ),
    ],
    swiftLanguageVersions: [.v5]
)

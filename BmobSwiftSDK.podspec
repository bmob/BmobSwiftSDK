Pod::Spec.new do |s|
  s.name             = 'BmobSwiftSDK'
  s.version          = '1.0.2'
  s.summary          = 'Bmob Swift SDK — 纯 Swift 实现的 Bmob 后端云 SDK，支持 iOS/macOS 双平台'
  s.description      = <<-DESC
    全新 Bmob Swift SDK，采用 async/await 并发模型，支持 SPM 和 CocoaPods 双通道集成。
    提供用户管理、数据表 CRUD、文件上传下载、云函数调用、ACL 角色管理、实时数据监听等功能。
  DESC

  s.homepage         = 'https://www.bmobapp.com'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Bmob' => 'support@bmob.cn' }
  s.source           = { :git => 'https://github.com/bmob/BmobSwiftSDK.git', :tag => "v#{s.version}" }

  s.swift_versions   = ['5.9']
  s.ios.deployment_target = '15.0'
  s.macos.deployment_target = '12.0'

  # 默认全部安装
  s.default_subspecs = 'All'

  # 全量安装
  s.subspec 'All' do |all|
    all.dependency 'BmobSwiftSDK/Core'
    all.dependency 'BmobSwiftSDK/Data'
    all.dependency 'BmobSwiftSDK/User'
    all.dependency 'BmobSwiftSDK/File'
    all.dependency 'BmobSwiftSDK/Cloud'
  end

  # Core — 加密/网络/配置
  s.subspec 'Core' do |core|
    core.source_files = 'Sources/BmobCore/**/*.swift'
    core.frameworks = 'Foundation', 'Security'
  end

  # Data — 数据 CRUD + 查询
  s.subspec 'Data' do |data|
    data.source_files = 'Sources/BmobData/**/*.swift'
    data.dependency 'BmobSwiftSDK/Core'
  end

  # User — 用户管理
  s.subspec 'User' do |user|
    user.source_files = 'Sources/BmobUser/**/*.swift'
    user.dependency 'BmobSwiftSDK/Core'
    user.dependency 'BmobSwiftSDK/Data'
  end

  # File — 文件管理
  s.subspec 'File' do |file|
    file.source_files = 'Sources/BmobFile/**/*.swift'
    file.dependency 'BmobSwiftSDK/Core'
    file.dependency 'BmobSwiftSDK/Data'
  end

  # Cloud — 云函数
  s.subspec 'Cloud' do |cloud|
    cloud.source_files = 'Sources/BmobCloud/**/*.swift'
    cloud.dependency 'BmobSwiftSDK/Core'
  end
end

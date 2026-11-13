# Saytile iPhone 档案阅读器

阅读器展示同一 Apple 账户的私有档案，支持搜索、选中文字和按需回听。模拟器候选使用 iOS 18 或更新版本的 iPhone Simulator。项目使用 XcodeGen，从 `ios/` 运行 `xcodegen generate` 后打开 `SaytileReader.xcodeproj`。

## 运行模拟器候选

解压 CI 附件中的 `SaytileReader-Simulator.zip`。在一台已启动的 iPhone Simulator 上运行：

```sh
xcrun simctl install booted SaytileReader.app
xcrun simctl launch booted app.saytile.iphone.icloud-candidate --public-reader-fixture
```

此参数只在 Debug Simulator 加载一条隔离档案和十二秒钟的确定性测试音。直接打开模拟器 App 可检查未连接 iCloud 时的状态。CI 使用同样的原生阅读、搜索、文件校验及 AVAudioPlayer 路径，保存 App、SHA-256、源码提交、XCResult 和原生截图。

真机 iCloud 验收需要与 Mac 候选相同的 Development CloudKit 容器和测试账户。创建 iPhone 开发签名配置后，给目标设置 `CODE_SIGN_ENTITLEMENTS=Development.entitlements`、匹配的开发 Team 及 `SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) SAYTILE_READER_DEVELOPMENT`。服务未验收前不用于生产分发。

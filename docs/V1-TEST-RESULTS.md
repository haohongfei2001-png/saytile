# V1 验证记录

## 2026-11-06 · 基线

- PR #1：远端 data-and-prototype / swift-contracts 全部 SUCCESS。
- 本机 `python3 scripts/check_integrity.py`：66/66 文件一致。
- 本机 `python3 tests/test_recovery_contracts.py`：37/37 通过。
- 本机 Swift 6 契约 + SwiftSmoke：8/8 Unicode 断言通过。
- 环境：macOS 27.0 (26A428)，arm64，Swift 6.4，Command Line Tools SDK。

这些是继承设计契约验证，不代表原生 App 已可用。原生验证将在实际执行后补充。

## 原生集成检查点

- `swift build`：完整 Saytile App 通过（CLT 27，State 属性包装器兼容）。
- `scripts/build-app.sh debug`：App 打包、Info.plist 校验及 ad-hoc codesign 校验通过。
- 打包 App `--smoke-test --data-directory <独立空库>`：启动、恢复、无权限请求、异步退出通过。首次发现退出死锁后已修复，见 `evidence/native/startup.log`。
- Apple SpeechAnalyzer 中文合成验证：10.616 秒，识别完成，尾句保留；见 `evidence/native-audio-probe.json`。
- 生产 VAD/保存/SQLite 加速负载：2091 秒虚拟输入，180 条独立原音、66.9 MB、全部封段，待识别队列保留；见 `evidence/native-audio-load.log`。非真实 30 分钟收音与能耗结果。
- 原生单测：源码类型检查通过，全量运行尚在处理 CLT Testing 插件/Framework 定位，不计入已通过测试数。

## 原生单测已执行

`scripts/test-native.sh`：**49/49 通过**（Swift Testing，真实 SQLite/文件系统/原生生产函数与隔离输入适配器）。测试含存储 33 项、输入 11 项、音频 5 项。

CLT 测试方案使用默认 Swift Build、临时构建目录及已安装 TestingMacros 插件。没有安装完整 Xcode，没有修改系统设置。首次运行发现父目录符号链接校验漏洞，已以逐层 lstat 修复后复跑全部通过；失败证据 `evidence/native-tests-initial-failure.log` 保留。

原生输入板离屏渲染已完成，`evidence/native/panel-empty.png` 展示实际 SwiftUI 内容，不是 HTML 原型。实际目标应用 AX/SPA 尚未验收。

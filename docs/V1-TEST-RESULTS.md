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

## 实时管线与实际系统验证

- 5 分钟实时生产 C ring → AVAudioConverter → WebRTC VAD → WAV/SQLite：6,615,000 输入帧，丢帧 0，10 段封存，原音 300.0 秒。wall 300.42s，CPU user+sys 3.14s（约1.05%单核平均）、max RSS 20.4MB。见 `evidence/native-audio-realtime-soak.log`；不包括 ASR、UI 或整机功耗。
- 正式打包 App 的中文合成音频识别通过，见 `evidence/native/app-speech-prepared.log`。首次未准备该 App 资产失败保存在 `app-speech.log`；已增加首次收音后自动准备。
- 硬件计数探针首次触发 Swift 6 MainActor 隔离崩溃；生产与探针 tap 改为 nonisolated 工厂返回 @Sendable 回调，修复后实际采集 49 buffers / 235200 frames，见 `device-probe-fixed.log`。没有读取、保存或识别环境样本；失败摘要保留 `device-probe-initial-failure.json`。
- 后台禁止激活的专用 NSPanel/NSTextView，真实 AX 局部中文/emoji 插入、UTF-16 光标、局部确认、前后文保留及前台 PID 不变通过：`evidence/native-ax-fixture.json`。不等同完整生产绑定/浏览器 SPA 测试。
- 生产 AppModel 的8项隔离检查通过：初始加载、历史不自动入板、明确复用、清板不删档案、当前语音、收藏、搜索及清理预览等待，见 `evidence/native-app-model.log`。
- 输入板（空/有文字）、档案详情、设置已经实际 SwiftUI 离屏渲染核看，见 `evidence/native/*.png`。没有启动外部浏览器。

本轮实机测试发现的问题均先修根因，再复验；没有将初次失败或权限未验证写作通过。

## 发布候选原生测试

最新全量 **69/69 原生测试通过**，6 suites，见 `evidence/native-tests.log`。新增持久草稿跨重启/独删原音/删记录保护、后台音频回调实际执行、首块登记前崩溃恢复等回归。没有用编译成功替代测试执行。

## 最终界面与草稿

`scripts/test-app-model.sh`：**16/16 通过**，包含持久草稿切换/重选、刷新不覆盖、保存时继续输入及退出保留空草稿。脚本曾错误链接旧静态库，现已统一先构建全部产品，失败记录保留在 `native-draft-probe-initial-failure.log`。

`scripts/test-startup-focus.sh`：打包 App 实际启动菜单栏与非激活输入板，3秒观察中前台 PID 不变，正常退出；未访问其他应用内容。实际符号检查修复了不可用的错误状态 SF Symbol，避免故障时菜单栏图标消失。

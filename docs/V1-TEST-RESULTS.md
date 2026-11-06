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

## 远端兼容修复记录

PR #2 的本机 Swift 6.4 编译与 Release 包验证通过，但远端 Xcode 26.6 / Swift 6.3.3 在 SwiftUI Binding 的 actor 方法引用适配时触发编译器 IRGen 崩溃（SmallVector），未把该 CI 写作通过。失败日志 `evidence/native-ci-compiler-failure.log` 保留；修复将显式闭包替代方法引用，仍运行完整原生测试与 App 构建。

## 最后故障回归

最新 **72/72 原生测试通过**、**16/16 AppModel 检查通过**。新增目录创建失败、实际写入 ENOSPC、末尾同步失败三项生产路径故障注入：记录均封段，无持久原音标缺失；有持久原音只发布此前已确认水位，文字保留。轮转失败不会误用上一文件的水位。5分钟正常管线结果无需因异常清理分支修改重复跑。

## 最终发布包

源码 `4c4430426050553a7df573053ff4cc582e45b3fa`：远端原生CI及设计契约CI全部通过，Swift6.3.3 Binding兼容修复已由实际CI证明。

Release DMG 校验通过；只读挂载中的App严格签名验证及启动通过；已安装到 `~/Applications/Saytile.app`，安装后再次签名和独立库启动通过。`evidence/native/release-manifest.json` 记录最终校验和、来源、验证和边界。同步工作目录会重新附加FinderInfo，使目录中的App副本严格签名失效；已改用校验完好的只读镜像和非同步Applications安装位置交付，没有修改系统安全或同步设置。


## 2026-11-06 · RC 收口启动

重新核对远端 main、PR #1/#2 与两条 CI；当前均一致，发布物仍是 Beta.1。已发现需要工程修复的候选缺陷：锁屏/撤权生命周期、ASR末尾定稿、输入取消及目标变更、draft搜索、并发打开资料库、输入板最新30条静默截断。将在独立合成环境建立复现及回归，不用历史 CI 或原型验证代替。

工作树发现7个未跟踪 ` 2` 副本，保留原状、不提交、不据此推断用户意图。


## RC 第一轮工程检查点

- `evidence/rc/native-checkpoint.log`：109 tests / 14 suites PASS。
- `evidence/rc/app-model.log`：21 checks PASS，含116条当前表达分页和断开设备UID保留。
- `evidence/rc/ui/run.log`：9张生产SwiftUI窗口渲染、5次真实AXPress；仅fixture PID、前台不变。离屏本进程AX树不展开，已改为透明非激活原生窗口+独立AX客户端；前期本地mouse探针仅模式成功，档案点击未通过，没有冒称全控件通过。
- 存储：9项真实进程/升级/写入故障；10万记录30万版本，partial写p95 0.14ms，清理时并发写p95 0.24ms。详细输出见RC-STORAGE-WORK。
- 输入：22单测、9原生后台全链路、WebKit页面变更/能力拒绝、20headless DOM检查。最初WebKit 5/5含延迟通知串扰，经隔离复查发现silentContext失败；根因修复为有界语义身份并重新回归，失败如实保留。详见RC-INPUT-WORK。
- 音频：30分钟墙钟、39,690,000帧零drop，60段1800秒、57.61MB。只包括ring/转换/VAD/WAV/SQLite，不包括真实麦克风、ASR或整机能耗。中文8条两声音实时TTS语料和Apple识别器对照披露错字，详见RC-AUDIO-WORK。

当前是检查点，不是最终RC签字。签名安装升级、最终CI及交叉审查仍在进行。

# PR #4 源码CI与候选交付 · 2026-11-06

远端源码1c907f6与本机252测试使用的87395e6整树同SHA。macOS26 native run42241293084成功（252项/25组、21AppModel、构建、合成原生窗口、隔离启动）；contracts run42241293137成功。sourceDirty=false的未安装preview.2 release/signature/smoke通过。26项离线评分现加入Ubuntu工作流，无云调用。

焦点验证不掩盖混合观察：首候选通过；远端同树身份重打包后一次发生前台改变，未归因；随后唯一一次带候选PID归因复测通过，候选从未前台且其他切换为0。证据保留，未据此声称长期无干扰或把失败归咎用户。真实识别精度/确认延迟未测。

---

# PR #4 集成回归检查点 2 · 2026-11-06

最终本机252 tests / 25 suites PASS，21项AppModel PASS，26项Python计分/来源/配置/准备入口测试PASS；继承契约验证通过。完整证据与失败记录在 `research/asr/validation/fusion-quality/README.md`。全量覆盖Store失败状态派发禁用、当前全部证据重验、未派发纠正、实际派发前缀、多目标、用户草稿、取消删除、真实终态、被拒绝仲裁审计和纯本地基线身份。

未以相交专项计数累加总数。独立审查从旧静态构建复现failed-expert→reserve缺陷，修复后同用例前后两个时点都NONE；首轮并发全量失败与最终绿结果均保留。真实云请求、准确率增益、确认延迟和账户费用仍NOT_RUN。

下一步只构建此提交的未安装候选并检查CI；CI并不能取代上述未测能力。

---

# PR #4 融合质量检查点 1 · 2026-11-06

- 新融合发布边界与原有多模型：41/41 通过；仲裁证据与英文协议：27/27 通过。新用例分别 9 与11项，交叉筛选计数不得相加当全量。
- 先复现：短复核错误宣布解决、Meta progress 被当音频范围、尚未派发定稿无法修正；red 日志保留在 `research/asr/validation/fusion-quality/`。
- 新协调器集成7项（其中两个参数化各2例）通过，包括未派发全文纠正、同PCM不重复音频复核、新PCM重查、实际派发保护、失败保留。首轮241项全量曾因并发旧状态触发不必要仲裁失败1项，修复后待最终全量，不隐藏失败。
- Corpus只读哈希：112/112，832.1804375秒；未采集麦克风、未上传语料。Keychain仅元数据、禁止弹授权、0匹配；没有读取秘密值。云模型准确率、服务可达性和真实延迟未测。

以下为RC1历史验证，计数不覆盖本轮源码。

---

> **最新 RC1：源码 `8906a9d` 在 macOS 26 上 122 项原生测试、21 项 AppModel、构建/原生渲染/启动通过；最终 DMG 安装升级 6 组、9 图/5 次 AXPress、合成中文与安装后启动通过。下文保留完整历史与失败，不将旧计数作为最新。**

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


## RC 最终根因与回归

1. 独立审查复现跨段倒序B→A：现在以创建序号作为绑定起点和最高派发水位；旧段迟到全文/尾部独立deferred，不重放，不阻塞C，删除B也不使水位倒退。
2. 一次118项全套出现4个新时序用例失败（保留native-timestamp-failure.log），专项及两次诊断没有复现。**未将SQLite精度猜测当结论**：4096个Double实测无损。改以同事务rowid区分绑定前后相同时间戳，统一boundAt与Unix时间比较，新增确定性新旧同tick回归；最终122项全部通过（input-full-final.log）。没有新增sleep或放宽旧内容边界。
3. 首轮云端111项native PASS，后续AppModel入口因SwiftPM和SwiftBuild模块目录不同而失败。修复明确静态库产物与两种模块布局，保留ci-layout-failure.log；本地经典SwiftPM与CLT均21checks PASS。
4. 实际打包App在a780aaa检查点待命300.03秒：user2.16s+sys0.43s，平均0.86%单核；maxRSS80.15MB，最终RSS约55.84MB。原始time口径和每5秒样本均保留（app-idle.json/log）。仅空隔离库、菜单栏/刷新，没有麦克风、ASR或整机功耗，不冒称最终发布SHA或72小时。
5. 音频真实AVAudioPlayer另有2项零PCM集成：跨块seek、自然结束、stop/shutdown/租约与删除保文，未采麦或有声外放。

最终发行验收将补充精确源码SHA、DMG散列、只读挂载签名、Beta App→RC App安装升级、正常重启及重复实例拒绝。


## macOS 26 兼容修复 · 最终CI揭示

`8b22e24` 在本机macOS27通过，但云端macOS26.6.2的系统SQLite对REAL→TEXT转换发生舍入，122项套件中精度/时间用例出现69项断言失败。此时才有明确跨版本证据；不能把先前macOS27的4096样本无损结论推广到旧系统。

已将StoreSQLite按SQLITE_FLOAT/INTEGER分别使用sqlite3_column_double/int64读取，再交Swift无损表示，UTF8文本路径保留，测试未放宽。现有6项精度/边界/NUL测试PASS，最终修复head仍必须通过macOS26 CI。原错误见 `evidence/rc/ci-sqlite-precision-failure.log`，本地修复回归见 `storage-real-precision-fix.log`。

## RC1 最终发行验证 · 2026-11-06

- 源码 `8906a9dc4b2ec186f634bb2c829d8eb0c1700679`，sourceDirty=false。[macOS 26 native CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42196920566/job/127822389253) 122 tests / 15 suites、21 AppModel、构建、9图、启动全部 PASS；[设计契约 CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42196920610/job/127822388691) PASS。摘录 `evidence/rc/ci-final-summary.log`。这已验证旧系统 SQLite 根因修复，测试未放宽。
- 最终 DMG SHA256：`fb001a8ad0c107570acc6d263e590e49eb5bb9827d617e30c72cbaa4c247ed2a`。只读镜像签名、独立安装、实际 Beta App 打开合成旧库→RC App 升级、三次重启、重复进程拒绝、强制退出恢复共6组 PASS。版本/草稿/固定/不确定派发及原音保留；RC启动0.530秒，三次重启0.161/0.162/0.164秒，仅为当前独立数据样本。
- 最终包生产 SwiftUI 9图与真实 AXPress 5次 PASS，作用域为透明非激活窗口与 fixture PID；输入板、档案筛选和保存实际执行，前台不变。紧凑详情及设置已再次视觉检查；不是 HTML。
- 最终包读取既有自编中文 TTS，ASR completed、error=none，含“请不要自动发送”和末尾“保留原始录音”；标点/数字展示与原文不同，原样输出保留在 `packaged-speech.log`。系统框架输出非致命 sandbox_extension 警告，识别和启动流程实际成功，未隐去日志。没有采集麦克风。
- 最终包启动焦点探针 PASS，退出0、frontmost_unchanged=true。已更新 `~/Applications/Saytile.app` 并保留旧包备份；严格签名和独立库 smoke PASS，未打开正式库、未自动收音。详情 `installed.json`、`installed-smoke.log`。
- 最终二进制/DMG/CI/证据归属集中在 `evidence/rc/release-manifest.json`。30分钟管线与5分钟待命仍准确归属较早工程检查点，没有被改写为最终包72小时验证。

上述通过不覆盖真人发音/噪声、完整用户前台浏览器插入、物理睡眠/锁屏/设备断开/TCC更改、多显示器/Spaces和整机能耗；剩余范围见最终验收文件。无临时用户操作要求。最终独立文案审查另收紧 README 的“检测到页面变化”措辞，不改变代码/安装包，不新增测试计数。

## 最终前台隔离尝试与后台回归

复用原有 NSTextView/WKWebView fixtures，增加可选短批次：真实 `AXInputAccess.frontmostSelection()` 前后仅加 fixture PID guard，不伪造 AX 对象；已有 AX 权限、只读键鼠事件年龄检查、30秒上限、用户操作/切走立即退出且不夺回焦点；日志不输出字段全文。编译、Python语法和diff检查通过。

一次执行在任何激活前以 `NOT_RUN` 退出（`evidence/rc/input-foreground-batch.log`）：空闲条件未满足。随后只读年龄诊断见最近keyDown/keyUp约1.27/1.18秒、鼠标约41秒；未发生的tablet事件年龄为系统uptime，排除检测实现误将它们当零的猜测。没有读取键值/坐标，不能归因事件来源；未重试前台模式。不能将编译或这次安全退出计为实际前台插入通过。

修改后的默认后台路径已重新执行：原生生产协调器+SQLite+真实AX 9项通过；WebKit 6类变化、无语义/截断拒绝与无发送通过，后台写入仍未确认且不重发。证据文件原样更新，不增加逻辑套件计数。生产源码和已验证DMG均未改变。

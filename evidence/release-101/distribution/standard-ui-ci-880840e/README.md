# Intel 标准 Sparkle UI：IconServices 阻塞与夹具修复

运行 `45530413100`／job `138924017967`／源码 `880840ec1c592d05e2ed1db28dccbb4153ff4c4e`，runner 为 `macos-26-intel`。完整 job 日志为 `job.log`。原始 artifact `14985211318` 的 41,215 字节 ZIP 和展开文件原样保留；ZIP SHA-256 `df214604faf8b0c8449b34343f51411581608d1b0e177606481d9e9f9fbd553f` 与 GitHub digest 一致，每个展开文件均逐字节核对。

## 实际结果

**PASS**：此前完整测试步骤成功，Swift Testing 七次运行合计 `4 + 13 + 12 + 1 + 9 + 8 + 535 = 582` 项，XCTest 30 项、0 失败；wire audit 52 cases、0 violations。计数来自本次完整日志，见 `suite-counts.json`，没有重复相加嵌套 XCTest 汇总。

**FAIL**：标准 UI 进程在原 45 秒总时限终止，实际 45.045 秒。x86_64 编译成功，进程 PID 16605；启动、controller 初始化和手动检查调用的 breadcrumb 均到达，最后阶段为 `check_for_updates_returned`。没有 loopback 请求、最终 native receipt 或截图。原始 `source_dirty=true` 保留，不擅自重写为 false。

## 已确认的阻塞点

40 秒取得的自身 PID 栈表明主线程同步等待链为：

`SPUUpdater.checkForUpdates` → `SPUStandardUserDriver.showUserInitiatedUpdateCheck` → `SUStatusController.initWithHost` → `SUApplicationInfo.bestIconForHost:27` → `NSImage imageNamed:NSImageNameApplicationIcon` → `NSWorkspace iconForFile` → `ISIconManager` 初始化 → 同步 NSXPC 回复等待。

SDK 栈用固定 Sparkle 2.10.1 的 x86_64 dSYM 符号化，其 UUID `788645BC-00DF-3B33-8358-F7C78E2DD52A` 与 CI sample 相同；原栈、符号化文本与 UUID 均已保存。官方 [SUApplicationInfo.m 第 27 行](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/SUApplicationInfo.m#L27) 的 blob SHA 和来源摘要见 `sdk-source-metadata.json`。

这不是 NSApplication 启动阻塞，也没有到达 notes／按钮断言或 feed 请求。同步等待阻止 main actor 继续执行原 20 秒 async deadline；外部 45 秒 watchdog 按预期保存栈并终止。**UNKNOWN**：托管 Intel VM 上 IconServices 不回复的底层原因，及是否涉及网络沙箱本地 IPC。尚不能归因为产品缺陷，也没有新增 AF_UNIX 例外。

## 修复范围

Intel 测试 job 不构建 `dist/Saytile.app`，旧夹具的可选图标复制路径因此不能提供产品资源。本次夹具按 `build-app.sh` 的同一 `SaytilePlate.png`、尺寸集合及编码 fallback 生成真实 `Saytile.icns`，总是填写 `CFBundleIconFile`。在调用默认 SDK 前，使用公开 `NSImage.setName(NSImage.applicationIconName)` 预加载并长期保留这份真实图标，且要求 SDK 原样的 `NSImage(named:)` 查询严格返回同一对象。新 receipt 记录源图／资源摘要、命名缓存断言及边界。

产品 controller、Sparkle SDK 和默认 user driver 没有修改；没有 swizzle、占位图、自制窗口或替代按钮。所有版本、notes、默认 SDK 按钮、Later、可见性／激活断言和完整 exercise 逐字保持；原 20 秒 deadline、45 秒 watchdog 与 loopback-only profile 逐字保持，见 `fix-verification.json`。该夹具验收**不包含动态系统 IconServices 服务行为**，不能据此宣称此系统服务已修复。

## 本机验证与限制

- **PASS**：纯图像 `.prohibited` 和 `.accessory` 两个独立进程，使用真实 575 `.icns`、原网络 profile，命名注册成功且 `NSImage(named:)` 返回同一对象；均 `isActive=false`、0 窗口，没有调用 activate 或启动默认 Sparkle UI。均为 arm64，不代表 Intel GUI 已通过。
- **PASS**：普通 native `iconutil` 生成的夹具图标与最终 575 App 图标逐字节相同，SHA-256 `65f50b1645187adbe06540ef8ea884b4abbfa650b435eaf62d4b0c1f946cf166`。
- **PASS**：完整更新后 Swift probe 的 Swift 6／warnings-as-errors 编译，以及本机 UI 拒绝守卫；`fixed-arm64-compile/receipt.json` 明确为 `NOT_RUN`。编译发生于独立 clone 的 dirty tree，准确源码摘要已保存。
- **保留未采用路径**：单纯设置 `applicationIconImage` 没有证明同一命名对象身份，结果为 false，原实验保存。受限执行环境的 `iconutil` 失败后使用现有 product fallback，输出 ICNS 容器字节与正式包不同；最初比较失败及双方摘要保存于 `restricted-encoding-comparison.log`。随后仅对图标资源生成作 native 权限复核，证明原生编码器输出完全匹配；没有覆盖或把这次初始比较说成通过。

**NOT_RUN**：补丁后的真实 Intel 标准弹窗。由主任务统一推送并读取一次 CI 的原始结果；本子任务没有自行 push、重跑或增加 runner。本机未运行 ASR、未打开可见标准更新窗口，未改动最终签名包、安装中的 533 App、生产数据或 Keychain。

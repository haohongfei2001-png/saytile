# Intel 标准 Sparkle UI 原始失败与诊断补丁

运行 `45520699343`／job `138891489076`／源码 `fcddb9088416c9ce8ce9974cda461cdaf0451966`，runner 为 `macos-26-intel`。完整 job 日志保存在 `job.log`；原始 artifact ZIP 与展开后的四个文件均保留。ZIP SHA-256 `3525361c0b28f737c6d85875dd34f2a73ca971badbe9ebb43c080ddb2a14388d` 与 GitHub 返回的 digest 相同。

## 完整测试计数

**PASS**：Swift Testing 分七个真实进程运行，`4 + 13 + 12 + 1 + 9 + 8 + 535 = 582` 项；XCTest 30 项、0 失败。XCTest 内层、外层重复输出同一汇总，不能重复相加。wire audit 为 52 cases、0 violations。步骤 3 已成功退出，之后的标准 UI 步骤独立失败。原行与摘要见 `job.log`、`suite-counts.json`。

## 标准 UI 原始结果

**FAIL（运行超时）**：固定 Sparkle 2.10.1 与 x86_64 target 编译成功。Python 启动原生进程后 45 秒超时；`native.log` 为空，没有 `native-receipt.json`、截图或 loopback 请求。不能把这个结果解释成 notes／按钮断言失败、网络规则失败或已复现的产品缺陷。

原 `source_dirty=true` 原样保留；该收据没有记录具体改动路径。本轮逐字核对 controller、Swift probe 和固定 signed feed 的摘要，它们与被测 fcddb90 提交一致，不把这个 flag 擅自改成 false。

## 无窗口本机诊断

`startup-diagnostic/` 保留源码、编译日志、运行日志和收据。全部在 **arm64** 上执行，不能替代 Intel 实际标准弹窗。

- 最小 NSApplication 的 `.prohibited` 启动：原网络 profile 与无 profile 两组均 PASS，didFinishLaunching、main-actor task 与恢复均到达。
- 只初始化原样 AppUpdateController、不开启自动检查、不手动检查的 `.prohibited` 夹具：两组均 PASS，configured／ready 为 true，没有默认 UI。
- 无窗口、不调用 activate 的 `.accessory` 启动：两组均 PASS，前后 `isActive=false`。

这些结果没有复现 CI 超时，也没有证明本地 IPC 被错误封锁。因此没有新增 AF_UNIX 例外、放松网络权限或在用户桌面调用标准 Sparkle 弹窗。

## 本次补丁与验证

只修复夹具静默超时无法定位的问题：Swift 在 main、NSApplication.shared、activation policy、delegate、controller init、manual check、notes、Later 前后写原子 `native-progress.json`，并同步写原生日志。Python 运行器在 40 秒仍未退出时仅采样自己创建的 PID 一秒，仍在原有 45 秒总时限终止进程，记录退出码及最后阶段。

**PASS（本机验证）**：Swift 6／warnings-as-errors 编译；新的运行器真实正常退出、exit 7 和超时三例。超时例在 45.004 秒被终止，sample 成功，未启动 UI。`assertion-preservation.json` 证明移除新增日志行后，完整 exercise 的原断言与动作逐字不变；原 20 秒 async deadline、产品 controller 和 loopback-only profile 也不变。

**UNKNOWN**：CI 的准确同步阻塞阶段和产品归因。**NOT_RUN**：补丁后的真实 Intel 标准弹窗。下一步由主任务统一推送一次 CI，读取最后原子阶段及自身 PID 栈，再作具体归因；不增加重试、不扩大时限、不把诊断补丁说成 GUI 已修复或通过。

本机 gh 读取普通 API 元数据成功，但日志／ZIP 的重定向下载各出现 EOF；随后 GitHub connector 取得完整日志与原 ZIP，并完成 digest 校验。没有把失败下载当成完整证据，也没有保存临时下载 URL 或访问凭证。

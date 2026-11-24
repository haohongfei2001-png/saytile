# 1.0.1 发行与更新验收

基线：`f3baa0a255931dbb16291690699790e3d54f8bde`；产品修复：`7483536`。实际最终安装/更新收据在完成后追加，不能用本节的定向测试代替最终包验收。

## 已复现与修复

`AppUpdateController.updaterShouldDownloadReleaseNotes` 不是 Sparkle 2.10.1 的协议方法，运行时不会调用。原源码对真实 SDK 的 selector 检查返回 false，原始失败保留于 `evidence/release-101/distribution/baseline-notes-delegate.json`。

现已实现正确的 `updater(_:shouldDownloadReleaseNotesForUpdate:)`。仅已验证签名 feed 中的 HTTPS 说明可下载；隔离夹具另允许 loopback。说明文件本身仍由 Sparkle 验签。既有 `shouldProceedWithUpdate` 同样要求 feed 签名成功，正式输入、资料与身份无变更。

实际控制器源码对固定 SDK 编译通过，使用 `-warnings-as-errors`；原生 selector 回归 PASS。此检查只替换模型的展示属性，没有替代 Sparkle，但不是整 App UI/说明展示通过。独立的原生 host 更新测试必须验证签名说明实际加载与损坏说明拒绝。

## 签名与外部授权

- **PASS**：现有 Developer ID `92B7E50A1D43D247EA7EA19A31DCA3E407435A42`，Team `ZB9D4T66QB` 可用。
- **PASS**：原有 Sparkle 账户 `app.saytile.updates.v1` 对隔离挑战签名，并由已发布的 `SUPublicEDKey` 独立验签；不生成新密钥，不导出私钥，不改变 Keychain。`key-continuity.json` 包含公开签名及摘要。
- **PASS（范围有限）**：现有公开 mandarin feed 签名有效，当前 0 个 item。该检查不代表候选已公开，也没有安装任何更新。
- **BLOCKED**：用户 Keychain 搜索列表及 Data Protection 属性中未发现 notary profile；相关环境配置名为空，标准 App Store Connect API Key 目录文件数为 0。所有检查均未请求密码数据、未读取 key 文件。CI secret 状态由主交付流程单独核实。

唯一所需的账户操作：账户持有人在本机为现有 Developer Team 配置一次 notarytool profile（见 `distribution/README.md`），无需把密码或 API Key 提供给聊天。配置完成后仍须真实提交最终包、等待 Apple 结果、Staple、Gatekeeper 与下载验收，不能把已有 Developer ID 签名说成公证通过。

## 可复现的更新工具

`distribution/create-update.py` 只准备 ZIP、带纯文字内联 Release Notes 的签名 Appcast 及收据，不上传、不发布。它检查干净源码 SHA、正式版本号、身份、渠道、已发布公钥、完整签名策略、Developer ID/hardened runtime/时间戳；归档用公开公钥独立验签。

`scripts/test-release-update.py` 保留两个真实版本的版本号、build 和可执行代码；临时重签名会改变 Mach-O 签名区，使用不执行的比较副本去除签名后核对完整代码字节，验证真实 Sparkle installer 的 1.0.0→1.0.1 升级、损坏包拒绝、新包离线启动、完整合成资料、模型缓存及旧包回退打开。

`scripts/test-native-update.py` 验证最终候选实际 host/controller 的退出保存、签名说明加载、损坏说明拒绝、真实 Sparkle 安装器及无参数重启。此旧夹具仍使用 1→2 build aliases，必须与真实版本测试分别报告。两项均保留独立 Bundle ID、资料与缓存，只复用既有签名工具内部访问账户。

## 当前检查状态

| 检查 | 状态 | 证据 |
| --- | --- | --- |
| 旧 notes selector 失败 | FAIL_REPRODUCED | baseline-notes-delegate.json |
| 修复后的真实 SDK selector | PASS | update-controller-probe.log |
| 更新配置包装断言 | PASS，20 项 | update-configuration.log |
| 新发行工具/公钥验签/篡改拒绝 | PASS，10 项 | release-preparation-tests.log |
| 真实 572→574 安装与回退 | PASS，旧候选 4ac4d90；公开 SHA 重绑定后需重验 | real-version-update-r3/receipt.json |
| 最终 host 签名说明/更新/重启 | NOT_RUN，待统一候选 | 不能以 selector 代替 |
| 标准 Sparkle 弹窗视觉交互 | NOT_RUN | 与 deterministic driver 分开 |
| 最终 App/DMG 公证、Gatekeeper | BLOCKED，缺现成公证授权 | credential-metadata.json |
| 生产 feed 更新/正式发行 | NOT_RUN | 主负责人统一放行后才执行 |

官方依据：[Sparkle 发行流程](https://sparkle-project.org/documentation/publishing/)、[Updater delegate](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html)、[轻量更新提醒](https://sparkle-project.org/documentation/gentle-reminders/)。生产继续固定 Sparkle 2.10.1；当前文档新增的 2.11 beta feed bundle-identifier 强制设置未冒称现有运行库已支持。

## 隔离升级首轮原始结果

- `real-version-update/`：**FAIL（测试问题）**。临时 Bundle ID 重签名必然改变 Mach-O 内嵌签名；首次脚本错误要求整 executable SHA 相等。发生在安装开始之前，原包未变。修正后比较无签名副本的完整代码字节，实际执行/安装副本仍保留并验证 Developer ID 签名，安装后还必须与下载的目标完整字节相等。
- `real-version-update-r2/`：**FAIL**。坏包被正确拒绝后，紧接着的独立 CLI 检查返回 Sparkle 1004，且没有第二次网络请求。原日志保留，不声称产品恢复已通过。
- `real-version-update-r3/`：**PASS，范围为 4ac4d90 候选**。下一检查之前只观察本次独立 fixture 的安装助手退出状态，两次连续无助手的观察间隔约 164ms；未清缓存、未杀助手、未重试同一检查。此次损坏包拒绝、572→574真实版本安装、签名及原始代码、离线合成档案、模型缓存和旧版回退通过。但未捕捉到未退出助手 PID，因此这支持退出时序相关的假设，不能声称已完全证明前次1004的根因。

全量 storage 进程回归与候选可能因工具/文档提交处于不同 SHA；更新收据保留 App源码和实际 storage test HEAD，同时严格比较 `SaytileKit`、`CAudio`、`CSQLite`、Package、探针及存储测试程序的完整 Git 输入树。只接受所有输入对象完全相等，不修改旧收据；真实代码变化仍需重新测试。相关正负回归包含“仅文档变化接受、存储变化拒绝、探针字节变化拒绝”。

主负责人随后因 GitHub 作者隐私策略对未推送提交改用公开 noreply（代码树不变），旧候选未覆盖。最终更新验收须绑定重新签名的公开源码候选；当前结果不能提前冒充该最终包通过。

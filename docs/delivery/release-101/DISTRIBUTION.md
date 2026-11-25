# 1.0.1（575）最终发行与更新验收

最终签名产品源码 `8f25ea3be642263daf22ff297f337026395840a6`，主程序 SHA-256 `43548784ae92bfc80c471d409be3f4df10e265a4ea97e8e1cc858b773b41499f`。**HOLD：未公证，不发布生产更新。**

575重新完成真实572→575升级、损坏更新包拒绝、离线档案打开、回退；6个Qwen研究缓存文件（712,777,119字节）SHA和mtime不变。实际575 host验证签名说明、篡改说明拒绝、退出保存和无参数重启；未触碰安装533或个人资料。源代码/签名/原始测试身份独立保留于 [最终更新证据](../../../evidence/release-101/distribution/final575/README.md)。

- 最终DMG SHA-256：`3c346eda3b1093a3d9374faf70a176353ad09ea350a9111696a32275621af25a`。
- 最终更新ZIP：55,577,621字节，SHA-256 `c6f65da61b200575bc296e9923f1ab770c745ee657ba376782d1b6d1e573cc16`。
- 最终签名feed SHA-256：`917e714957a8810cea8cdb5f83c9da4093a62c8fbbbe7f23e6fcfee6089706b6`。
- 解包后136个文件/符号链接及67个目录权限与原App完全相同，原公钥验签和codesign严格验证通过。
- 标准Sparkle默认弹窗在独立CI桌面验收，不在用户桌面强行夺取焦点。最新结果见统一ACCEPTANCE，不能用自定义driver代替。
- 时间戳连接诊断：默认连接两次失败，独立RFC3161合成请求确认Apple HTTP端点有效，HTTPS路径失败；显式Apple端点签名通过，安全时间戳与严格验证仍为必须条件。没有改系统代理、Gatekeeper或quarantine。

目录 `dist/1.0.1/` 只保留575交付产物；574移至独立临时历史证据目录，原哈希不变。生产feed和官网仍为原发布状态；候选feed中的未来URL不是当前可用的公开下载。

## 历史574与原始失败记录（保持原验收身份）


基线：`f3baa0a255931dbb16291690699790e3d54f8bde`；产品修复原始提交：`7483536`。最终更新验收绑定 **1.0.1（574）／`73ad857442964437929819ba9965f6bcfdcefd27`**，主可执行文件 SHA-256 为 `d6274b3dee146f5111b980175c86dabe0a9d6b00edbb888276f00db98be25445`。本页仅裁决发行与更新部分，产品质量及 CI 由统一交付报告汇总。

**发行结论：HOLD。** 已完成真实隔离升级、原生更新控制器、回退和既有签名密钥闭环；未配置公证授权，生产空 feed 保持不变，没有公开发布或替换安装 533。

## 已复现与修复

`AppUpdateController.updaterShouldDownloadReleaseNotes` 不是 Sparkle 2.10.1 的协议方法，运行时不会调用。原源码对真实 SDK 的 selector 检查返回 false，原始失败保留于 `evidence/release-101/distribution/baseline-notes-delegate.json`。

现已实现正确的 `updater(_:shouldDownloadReleaseNotesForUpdate:)`。仅已验证签名 feed 中的 HTTPS 说明可下载；隔离夹具另允许 loopback。说明文件本身仍由 Sparkle 验签。既有 `shouldProceedWithUpdate` 同样要求 feed 签名成功，正式输入、资料与身份无变更。

实际控制器源码对固定 SDK 编译通过，使用 `-warnings-as-errors`；原生 selector 回归 PASS。该检查只替换模型的展示属性，不替代 Sparkle，也不独立证明整 App UI/说明展示。最终原生 host 测试另外证明：签名 feed 中的签名说明实际下载并交给 user driver，字节被篡改的说明被 Sparkle 拒绝（2001／3002），没有交给显示回调。

`item.signingValidationStatus == .succeeded` 表示 **feed** 验签成功，仅 enclosure 的 `edSignature` 不能代替它。本次正例对 feed、archive、外部 notes 分别签名；正式待发布 feed 采用受 feed 签名覆盖的内联纯文字说明，不增加远程 HTML 请求。

## 签名与外部授权

- **PASS**：现有 Developer ID `92B7E50A1D43D247EA7EA19A31DCA3E407435A42`，Team `ZB9D4T66QB` 可用。
- **PASS**：原有 Sparkle 账户 `app.saytile.updates.v1` 对隔离挑战签名，并由已发布的 `SUPublicEDKey` 独立验签；不生成新密钥，不导出私钥，不改变 Keychain。`key-continuity.json` 包含公开签名及摘要。
- **PASS（范围有限）**：现有公开 mandarin feed 签名有效，当前 0 个 item。该检查不代表候选已公开，也没有安装任何更新。
- **BLOCKED**：用户 Keychain 搜索列表及 Data Protection 属性中未发现 notary profile；相关环境配置名为空，标准 App Store Connect API Key 目录文件数为 0。所有检查均未请求密码数据、未读取 key 文件。CI secret 状态由主交付流程单独核实。

唯一所需的账户操作：账户持有人在本机为现有 Developer Team 配置一次 notarytool profile（见 `distribution/README.md`），无需把密码或 API Key 提供给聊天。配置完成后仍须真实提交最终包、等待 Apple 结果、Staple、Gatekeeper 与下载验收，不能把已有 Developer ID 签名说成公证通过。

## 可复现的更新工具

`distribution/create-update.py` 只准备 ZIP、带纯文字内联 Release Notes 的签名 Appcast 及收据，不上传、不发布。它检查干净源码 SHA、正式版本号、身份、渠道、已发布公钥、完整签名策略、Developer ID/hardened runtime/时间戳；归档用公开公钥独立验签。

`scripts/test-release-update.py` 保留两个真实版本的版本号、build 和可执行代码；临时重签名会改变 Mach-O 签名区，使用不执行的比较副本去除签名后核对完整代码字节，验证真实 Sparkle installer 的 1.0.0→1.0.1 升级、损坏包拒绝、新包离线启动、完整合成资料及旧包回退打开。小型模型 marker 仅是 canary；本次另传入授权研究模型路径，将真实 Qwen 权重 APFS clone 到隔离 `LocalModels`，比较全部文件 SHA-256 和修改时间。没有读取生产缓存、运行模型或下载权重。

`scripts/test-native-update.py` 验证最终候选实际 host/controller 的退出保存、签名说明加载、损坏说明拒绝、真实 Sparkle 安装器及无参数重启。此旧夹具仍使用 1→2 build aliases，必须与真实版本测试分别报告。两项均保留独立 Bundle ID、资料与缓存，只复用既有签名工具内部访问账户。

## 当前检查状态

| 检查 | 状态 | 证据 |
| --- | --- | --- |
| 旧 notes selector 失败 | FAIL_REPRODUCED | baseline-notes-delegate.json |
| 修复后的真实 SDK selector | PASS | update-controller-probe.log |
| 更新配置包装断言 | PASS，20 项 | update-configuration.log |
| 新发行工具/公钥验签/篡改拒绝 | PASS，10 项 | release-preparation-tests.log |
| 真实 572→574 安装与回退 | PASS，最终公开源码 73ad857 | final-release-update/receipt.json |
| 最终 host 签名说明/更新/无参数重启 | PASS，实际 App；1→2 fixture aliases | final-native-update/receipt.json、events.jsonl |
| 损坏 archive 拒绝／损坏 notes 拒绝 | PASS，4005／2001+3002 | 两层更新原始日志 |
| 合成 SQLite、用户编辑、草稿、段落、原音 | PASS，2 条录音、4 修订，完整摘要相同 | final-release-model-cache/receipt.json |
| 真实 Qwen 模型缓存升级／回退保护 | PASS，6 文件／712,777,119 字节，全部 SHA 与 mtime 不变 | final-release-model-cache/receipt.json |
| 实际设置「检查更新」控件与线上空 feed | PASS，外部 AXPress，未激活窗口、未抢焦点、未安装 | final-native-update/receipt.json、native-settings-about.png |
| 原身份最终 ZIP 解包与完整性 | PASS，136 个文件／符号链接，内容及 mode 与最终签名 App 相同 | final-prepared-update/extraction-receipt.json、bundle-manifest.json |
| 标准 Sparkle 弹窗视觉交互 | NOT_RUN；修复后的 CI 因 ARM runner 容量未执行 | standard-ui-ci-9a01841/、standard-ui-ci-de45b0f/ |
| 最终 App/DMG 公证、Gatekeeper | BLOCKED，缺现成公证授权 | credential-metadata.json |
| 生产 feed 更新/正式发行 | NOT_RUN | 主负责人统一放行后才执行 |

证据目录均位于 `evidence/release-101/distribution/`。最终原生设置截图来自实际 `SettingsView`；为防止更新到生产 App，截图仍显示夹具版本 `0.18 / build 2`，只证明控件和布局，不能冒充实际 1.0.1 版本展示。标准 Sparkle 更新弹窗没有经过视觉点击验收；已实测的是实际更新说明验证／交付回调、原生设置按钮及完整安装链路。

### 标准弹窗的不抢焦点可行性检查

完成一次源码检查，没有启动会抢焦点的产品路径，也没有新增测试架构或修改产品。最终候选内 Sparkle 为 2.10.1，二进制 SHA-256 `978b6e7759c9f676385fe5077c3302cc9d322021adbcaeaff45494eea64610eb`。该 tag 与现有 CLI 固定 commit `ab7d71291238df6e0492143b120c9b696a35f603` 的两个 UI 源文件逐字相同，源码摘要与行号保存于机器收据。

- 真实 `AppUpdateController.swift:52–55` 调用手动 `checkForUpdates()`。默认 [`SPUStandardUserDriver.m:538–558`](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/SPUStandardUserDriver.m#L538) 在显示检查窗口前请求激活；新版本弹窗的手动路径 [`176–192`](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/SPUStandardUserDriver.m#L176) 同样先激活非前台 App。内部激活方法 [`129–134`](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/SPUStandardUserDriver.m#L129) 调用 `activateIgnoringOtherApps:YES`。
- 默认 driver 的自动提醒可在后台工作，但 Saytile 的实际 delegate 在 `AppUpdateController.swift:125` 返回 false，让用户从设置主动查看。改用另一 delegate 来显示后台弹窗不能证明现有手动产品路径。
- 当前 `UpdateReview.swift:140,165` 使用 `.prohibited` 与 deterministic driver；设置截图在 `196–200` 临时使用 `.accessory` 加专门的 nonactivating NSPanel。Sparkle 默认窗口不具备该夹具的非激活约束。Apple 明确规定 [`.prohibited` 不能创建窗口或激活](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/prohibited)，因此没有强行创建窗口、swizzle 激活函数或拿隐藏 nib 截图冒充完整交互。

结论保持 **NOT_RUN**，这不是更新逻辑 FAIL。剩余最小范围是在独立交互式 macOS 桌面会话进行标准手动弹窗验收，或集中安排一次可取得前台的检查；无需重跑安装、语料或存储回归。

随后按主交付任务要求，在已有 `native` CI job 增加约 200 行的专用 probe，不新增 runner，也不修改产品。`StandardUpdateUIProbe.swift` 与原样 `AppUpdateController.swift` 一起编译，只有 AppModel 展示字段使用既有小型替身；不传自定义 user driver，因此由生产控制器创建 `SPUStandardUserDriver`。固定公钥和逐字保留的已签名 inline-notes feed 来自上方最终待发布文件，CI 不需要任何签名私钥。

该探针只允许在显式启用的 GitHub Actions 环境运行 UI。本机完成 Swift 6／warnings-as-errors 编译和本机 UI 启动拒绝检查，没有激活任何窗口。CI 会在独立桌面显示真正 `SUUpdateAlert`，验证新旧版本、完整说明及 Install/Later 原生按钮，保存窗口截图，点击实际 Later 控件并验证关闭及控制器恢复。探针进程仅允许 loopback 网络，禁止公共网络；不点击 Install、不下载安装、不加载模型。机器收据明确标记 `full_product_ui=false`，不能冒充整个实际 App 的 UI 验收。

首轮结果以 CI 的 `Saytile-standard-update-ui` artifact 为准。编译成功不是 GUI PASS；本地原始编译环境失败、修复后的编译收据与运行拒绝日志均保留于 `standard-ui-compile/`。

首轮实际运行 `45461101374`／job `138683564370` 在源码 `9a018417a743e2cd8c4df5249f226e10a022c012` 上 **FAIL（夹具）**：Seatbelt 不接受网络规则地址中的 `127.0.0.1:*`，`sandbox-exec` 在 Swift 探针启动前以 65 退出；无窗口、无 loopback 请求。原始 artifact ZIP、全部展开文件及完整 job 日志保留于 `standard-ui-ci-9a01841/`，artifact SHA 与 GitHub 返回摘要一致。

仅把测试 profile 的主机写法改为 `localhost:*`，仍然只允许 loopback。无 UI 的本机网络回归复现旧规则 exit 65；新规则收到真实 loopback 响应，并以 `EPERM` 立即拒绝保留测试网段 `198.51.100.1:9` 连接。没有改变产品或降低 UI 断言。旧失败收据将“请求使用的模式”提前写为 runtime_started/public_network_denied，已原样保留并在 diagnosis 中解释；新 runner 分别记录启动请求、实际 native receipt 与成功结果。标准窗口结论仍待主负责人统一推送后的 CI，不能将这次网络回归称为 UI PASS。

修复后的源码 `de45b0fb3c83e1fa13b6067a47b0342772e309ed` 对应 run `45466204990`／native job `138701660848` 被 GitHub 以 hosted ARM 容量不足取消：`runner_id=0`，没有任何 step。原始 check-run、job、annotations 及摘要保留于 `standard-ui-ci-de45b0f/`。这是 **BLOCKED_CI_CAPACITY**，既不是新 UI FAIL，也不是修复已通过；本代理没有触发重试或在用户桌面运行探针。

## 最终待发布文件

目录：`/private/tmp/saytile-release101-update-prepared/`。该目录没有上传，feed 的未来下载 URL 当前不能当成公开可用链接。

- `Saytile-1.0.1-update.zip`：55,577,565 字节；SHA-256 `b7417f53db6a49911ec15059376d2800456f09f16ae5eb351cc9bcf49f52a2d8`。
- 签名 `appcast.xml`：SHA-256 `f2c372c76b374449313f1e21a3a4046f87013264b607d34c3cec69351de81622`。
- 原有公开 Ed25519 公钥独立验签 PASS；ZIP 解包后 `codesign --verify --deep --strict` PASS，136 个 bundle 条目逐项 SHA／mode／symlink 与原签名候选完全相同。解包副本未启动、未注册 Launch Services、未移除 quarantine。
- 收据、Appcast 及完整 manifest 已入库于 `final-prepared-update/`；55 MB ZIP 保留本机交付目录，不放入 Git 历史。
- 候选 release notes 如实写明尚未公证／发布。公证、装订或任何包修改后必须重新生成签名 ZIP、签名 feed 和 SHA；本次签名不能覆盖未来修改的包。

官方依据：[Sparkle 发行流程](https://sparkle-project.org/documentation/publishing/)、[Updater delegate](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html)、[轻量更新提醒](https://sparkle-project.org/documentation/gentle-reminders/)。生产继续固定 Sparkle 2.10.1；当前文档新增的 2.11 beta feed bundle-identifier 强制设置未冒称现有运行库已支持。

## 隔离升级首轮原始结果

- `real-version-update/`：**FAIL（测试问题）**。临时 Bundle ID 重签名必然改变 Mach-O 内嵌签名；首次脚本错误要求整 executable SHA 相等。发生在安装开始之前，原包未变。修正后比较无签名副本的完整代码字节，实际执行/安装副本仍保留并验证 Developer ID 签名，安装后还必须与下载的目标完整字节相等。
- `real-version-update-r2/`：**FAIL**。坏包被正确拒绝后，紧接着的独立 CLI 检查返回 Sparkle 1004，且没有第二次网络请求。原日志保留，不声称产品恢复已通过。
- `real-version-update-r3/`：**PASS，范围为 4ac4d90 候选**。下一检查之前只观察本次独立 fixture 的安装助手退出状态，两次连续无助手的观察间隔约 164ms；未清缓存、未杀助手、未重试同一检查。此次损坏包拒绝、572→574真实版本安装、签名及原始代码、离线合成档案、模型缓存和旧版回退通过。但未捕捉到未退出助手 PID，因此这支持退出时序相关的假设，不能声称已完全证明前次1004的根因。

全量 storage 进程回归与候选可能因工具/文档提交处于不同 SHA；更新收据保留 App源码和实际 storage test HEAD，同时严格比较 `SaytileKit`、`CAudio`、`CSQLite`、Package、探针及存储测试程序的完整 Git 输入树。只接受所有输入对象完全相等，不修改旧收据；真实代码变化仍需重新测试。相关正负回归包含“仅文档变化接受、存储变化拒绝、探针字节变化拒绝”。

主负责人随后因 GitHub 作者隐私策略对未推送提交改用公开 noreply（代码树不变），旧候选未覆盖。上方 `final-*` 三组升级证据均重新运行于最终公开源码 `73ad857`，没有用旧 4ac4d90 收据替代；前两次失败和旧候选 PASS 作为原件继续保留。

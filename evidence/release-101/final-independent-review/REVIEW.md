# 1.0.1（576）最终源码安全复核

结论：**未发现新增 P0/P1。静态复核不构成发行 READY，也不宣称原 Chrome 现场已修复。**

- main：`f3baa0a255931dbb16291690699790e3d54f8bde`。
- 冻结产品：`2d12129f2031fdf827d51fa1796d155e79243e07`，1.0.1（576）。
- 观察到的整合 HEAD：`27e758662ec00708d56ae063561aaec0dc578b74`。当前 Sources/packaging/Package 与冻结产品无差异。
- 相对 main 的产品差异完整清单：7 个 Swift 文件，以及 VERSION/BUILD_NUMBER；逐文件 blob 与 SHA-256 见 receipt.json。额外变更为测试、评分及验收工具，不属于运行代码。
- 本轮没有运行测试、构建、模型、App、浏览器，或访问用户资料。AX 两项修复由本代理主写；这里是单独的只读复核轮次，**不冒称 AX 获得了另一作者的独立审查**。首次使用和更新变更由其他作者实现。

## 输入路径

1. **未知不等于可写。** `InputAccessibility.swift:85–97,485–488` 缺失/空 AXRole 抛出 unsupported，不生成可写快照；明确 enabled==false（已禁用）立即返回不可编辑，已知非编辑角色同样返回 false。enabled 属性缺省行为保持既有兼容契约，没有新增放行。
2. **写入前检查未改变。** `InputCoordinator.swift:187–198,350–408` 与 `InputAccessibility.swift:137–146` 仍要求完整快照、同目标、空选区及周围全文证明。缺失 role 无法用于首次绑定或新写入；Web 不降级为盲目粘贴。
3. **未知路径只保留对一次已发出写入的确认机会。** `InputCoordinator.swift:241–269` 必须是 continuous、可观察所有权、已有派发、未完成证明、不是 correction 且已有 expectedField。第二次 content/selection 通知直接使绑定失效；focus/document/layout 同样不会被重试掩盖（203–229）。
4. **证明次数、完整性和预算未变。** `275–302` 仍为最多四次、间隔220ms，只捕获 unsupported；任何已知身份/字段不等或其他错误立即拒绝。遇到读取缺口后计数归零，必须取得两次完整一致的 snapshot + UTF-8 全字段 witness，期间 generation 与 observedEditSequence 不变。`InputAccessibility.swift:238–264` 在全文读取前后再次校验快照并核对 UTF-16 长度，没有把部分范围当全文。
5. **不重发，不复活绑定。** `339–358,408–429,460` 仍只有一次 dispatch，之后循环全是读取；未知投递仍保存 unverified。invalidate 清空目标和运行中所有权并递增 generation（305起）。缺口后失效、取消或用户编辑不会因后来读到相同内容而自动重新绑定。
6. **迟到修订保护未变。** `490–546` 原有 owned 范围、全文、generation、取消和只写一次检查保留。新的 throwing witness 只服务已发出写入后的只读确认，不绕过 replaceOwned 写入前校验。普通复制、自动发送和窗口焦点行为未改。
7. **诊断无内容泄露。** 新增原因只有 `editor-role-unavailable`、`editor-disabled`、`editor-role-not-editable` 三个固定枚举式字符串；不记录原始角色、页面、前后文或私人身份。

## 首次使用、权限与更新整合

- 五个 App 文件与已复核的575逐字一致，不存在此次整合丢失或回退。`AppModel.swift:592–598` 在 MainActor 上等待资料恢复，检查已有文字/退出状态，一次性偏好先写后展示；`SaytileApp.swift:260,443–445` 仅正常启动展示 models 页。此路径不绑定输入、不请求麦克风、不改云端选择。
- `AppModel.swift:1020–1030` 只在非运行且已拒绝权限时打开系统设置；starting/listening/speaking 仍可暂停。仅增加恢复入口，没有清空原音、档案、草稿或修改资料身份。
- `LocalModelSettings.swift:154–158` 查询 availability，并验证选中模型仍相同；不会因查看模型页面启动识别或云端服务。准备文案区分模型就绪和麦克风权限。默认模型只是重新排序，没有新增模型、改变运行选择或第二路 ASR。
- `AppUpdateController.swift:68–89` 使用 pinned Sparkle 真实双参数 selector，先要求签名 appcast，再限制生产 HTTPS；HTTP例外仅限已有隔离fixture和127.0.0.1。原 shouldProceed 签名与版本升级检查不变。
- `AppUpdateConfiguration.swift:43–61` 的身份/channel、公钥、signed-feed、过期策略、解包前校验、禁用自动安装和禁用系统画像约束与 main 相同。修复 notes selector 没有引入新更新来源或安装授权。
- `SettingsView.swift:38` 仅改为显示真实版本。Bundle ID、存储路径、Keychain契约、数据库迁移、ASR/音频保存实现、包依赖和更新信任配置均未改变；明确核对的不可变文件见 receipt。

## 剩余证据边界

- 原880840e Chrome失败完整保留。其 editable=false 原因可能是 role 丢读，也可能是 enabled 实际变为false；旧日志无法区分，根因仍 **UNKNOWN**。新枚举日志和最终真实前台CI才能进一步裁决，不能由本复核自动改成PASS。
- 已有21项role故障注入、16项witness回归是合成OS元数据+真实协调器/SQLite；它们不等于576真实Chrome/Edge/Safari已通过。575及更早原生、语料、升级收据保留各自原SHA。
- 本轮未验证新签名包、公证、Gatekeeper、标准Sparkle弹窗、实机麦克风或物理断电。发布裁决继续以主交付方最终收据为准；本报告不解除现有HOLD。

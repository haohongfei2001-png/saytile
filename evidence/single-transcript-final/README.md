# 最新整合补充（优先于下方88c8e89历史切片）

运行时 `3cd8ebcbc94e7536ea8d4ccfd4474b72e9fd2b46` 已保留 PR4 79601ce / PR5 4fa637a 的最新删除失败隔离及独立测试偏好修复。Mac完整测试 **329/329（39 suites、无skip）**，AppModel **25/25**，评分 **43＋20**、设计契约通过；运行前后SHA一致。新运行时的原生UI **15视图/6组控件**均通过，无窗口激活、麦克风、外部前台变化。

真实AX校验不能只写全绿：新运行时首轮在初始插入后触发通用 `forbidden full-value/key/paste/payload attempt`，当时未记录各项计数，**无法归因**；日志与失败summary原样保留。增加细分计数、未改变生产源码或放宽断言后，新独立fixture复核 **5/5** 通过，所有可见计数为0。复测证明该次真实AX成功，不证明首次信号已被根治。目标选择仍为注入的精确测试PID，ChatGPT/Codex真实目标未验，原生外部输入发布门槛仍保持关闭。见 `native-reconciled-first-failure.*`、`owned-native-console.log`、`owned-native.json`。

最新两项CI均SUCCESS：native [42289851047](https://github.com/haohongfei2001-png/saytile/actions/runs/42289851047)，design [42289851010](https://github.com/haohongfei2001-png/saytile/actions/runs/42289851010)。最新Release候选见 [artifact 13539572392](https://github.com/haohongfei2001-png/saytile/actions/runs/42289851047/artifacts/13539572392)，App ZIP SHA256 `9ed2465811d982f5eab214fa4393235cdd36dcfe91a1f8cfe041badec6f01715`。实际内嵌临时合并SHA `5da0b18fb100a05f838fd3d133dff3e42fea625b`，tree与3cd8ebc一致、dirty=false、arm64、可执行权限保留；ad-hoc签名、未公证/未安装。

最新源码与候选身份以 `RECEIPT.json` 为准。下方88c8e89及它的CI、ZIP哈希仅为此前通过的精确历史切片，不冒充新运行时。真实A–E评测仍NOT_RUN，F不可用；生产main/RC1未变。

---

# SingleTranscriptEngine 核心工程验收与候选交付

更新：2026-11-07。**核心源码已实现并通过工程验收；真实云端识别准确率、目标应用兼容性与长时能耗仍未验收。** 本报告优先于目录中 earlier checkpoint，不把测试替身当云结果。

## 精确身份与同步

- PR #4：`a602236ea48f7140b57c46e916bae4c5d43f5cd9`；PR #5：`2018c0b02abc20b9575868e32cc2f81c03d833ac`。git 祖先检查均通过；不是仅凭 mergeable。
- PR #6 验证运行时：`88c8e8927be6ce9041ab2541e07c6d72daff2446`。Mac 全套运行前后 SHA 一致；验证产生的 evidence 日志不改变运行时源码。
- CI 构建的是临时合并提交 `f8fe3578c83c0e98f316b172af8b3f4c3dfcef3e`，其完整 tree 与 88c8e89 **相同**：`4ace45b660c67006a7aea1bb928d7c719fccce9b`。二进制内嵌的是这个真实合并 SHA，不伪称直接构建88c8e89。
- 之后新增真实 AX 验收脚本/证据，未改变 Sources、Package.swift、packaging、构建脚本。main/安装RC1/生产资料未变，无 force push。

## 实际完成

双平等 ASR 接收同一完整PCM；一个 GPT-6 持久 WebSocket 文本融合会话；280ms事件合并、候选清单增量和lineage、失效隔离、缓存失效重建、同模型HTTP回退。即时预览与外部派发资格分开，GPT认可之前不能因为两ASR一致就自动外发；结束讲话后必须最终复核。未加入其他AI复核链。

Apple结果进入Candidate/Store。云识别连接失败时取消旧代次，从已持久化原音分块回放给本地Apple并跟随新音频；本地不可用则排队，后续云恢复有界退避。当前本地locale为zh-CN，不承诺离线中英准确率等同云端。

原音按真实sample range跨块读取，每次分配上限1MiB，长音频迭代读取；移除12MB整段生命周期缓存。存储、采集、模型任务和输入相互隔离。

外部修正建立精确所有权：仅初次插入已确认后登记；实际写入前核对目标、选区、原文、用户编辑和当前批准版本，在SQLite先预留一次操作，再通过AXSelectedTextRange/AXSelectedText局部替换。失败不自动重试、不全框覆盖、不粘贴整段、不回车/发送。schema4保留既有数据、修订、Keychain UUID及输入账本；长度变化后的后缀继续正确。

用户只见一份文字，无候选/版本挑选或主辅模型选择。保留一次BYOK连接及独立授权；没有模型开关要求用户逐句选择。内部证据与用户编辑保护保留。

## 已执行验证

| 层次 | 结果 | 证明边界 |
|---|---|---|
| Mac完整原生测试 | 326/326，39 suites，无skip | 含真实独立Keychain和静音播放器，不是云质量 |
| 生产AppModel隔离探针 | 25/25 | 原生状态、草稿、退出与输入集成 |
| 离线评分 | 新20/20＋原43/43 | 验证评分及证据一致性，不能当真实ASR分数 |
| 设计契约 | PASS | 见verification.json及日志 |
| 原生SwiftUI | 15视图、6组交互；12 AXPress、2 AXSetValue、2原生编辑器提交 | 合成独立窗口；无候选激活、无麦克风、无外部前台变化 |
| 原生AX精确修正 | 5/5＋安全检查PASS | 真正独立NSTextView进程、生产AX适配器/Store/Coordinator；显式注入该测试PID，非真实用户目标解析 |
| GitHub native CI | SUCCESS，run42287983002 | 编译、全部测试、25AppModel、CLI、原生渲染、启动、Release包上传 |
| GitHub design CI | SUCCESS，run42287983169 | 精确同HEAD |

真实AX覆盖：50→500/emoji长度改变后继续追加；用户编辑拒绝覆盖；选区变化；目标变化；setter拒绝与不重试。五场景均保留用户前后文，不改剪贴板、不发键盘/Return、不整框替换。它不证明ChatGPT/Codex及所有网页提供相同AX能力；能力不满足则pending。

先前工作器沙箱内Keychain/播放器/AX被阻断的记录原样保留；上述是父流程在同一Mac独立fixture的实际成功复核，未绕过或修改权限、未向用户要求测试。

## 候选

`1.0.0-engine.single-transcript.2`，arm64 Release，ad-hoc签名，未公证，未替换安装。见[GitHub候选](https://github.com/haohongfei2001-png/saytile/actions/runs/42287983002/artifacts/13538896933)。内层App ZIP SHA256：`83bef0041a183eb6a28062bfa745b6c66c03ad7f22b9c9281e8a24367b01a6fd`。完整来源、二进制和外层artifact哈希见RECEIPT.json。

## 真正未完成的外部验收

A–E真实模型比较仍是NOT_RUN：Saytile专用Keychain元数据0项，未发现生产云配置、云开关false，未读取密钥值或弹权限提示。112现有音频/冻结24及336历史结果已复用准备，120条A–E命令未执行；所有真实错误率/延迟为null，而非0。Qwen Message＋AssemblyAI仅为工程默认，不能称为已测最佳。缺凭据时没有擅自创建付费服务或上传私人录音。

F为NOT_AVAILABLE：GPT-6 Astra官方模型页Audio not supported。持久Responses文本流不等于听音，其他OpenAI音频模型不能冒称GPT-6。尚未完成实际麦克风长时讲话、具体ChatGPT/Codex目标修正和24/72小时墙钟能耗验收。长音频加速回放不替代墙钟运行。

工程PR保持Draft，不合并main，质量/发布准入保持关闭。无需用户录音、标注、收集日志或测试。

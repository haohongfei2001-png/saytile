# Saytile V1 整合候选

分支从 PR #16 的交付提交 `843a6a205c2471adb6c1195b6c9370f34c3710ed` 派生，承接实际安装包源码 `a55d51a1`。PR #10、#11、#12、#13、#14、#15、#16 的最新 head 均为该提交的祖先。PR #6 头部另有六个机器结果提交。PR #9 的原图契约通过 #10 的整合进入产品，原图保持原文件。RC1 和冻结 RC2 作为升级输入。

| 功能 | 继承来源 | 既有验证范围 |
|---|---|---|
| 原音先写盘、系统生命周期、外派范围所有权 | #6 / #10 | 原生、隔离麦克风与设备收据，部分物理条件受限 |
| 玻璃面板、三态、两个操作 | #9 / #10 | 签名窗口及批准参考图 |
| 连续时间轴、草稿、原音、旧库迁移 | #11–13 | 真实 TextKit、SQLite 和隔离 Keychain |
| 本机、自带密钥与托管服务 | #14–16 | 协议、授权和本机服务状态。真实付费识别本轮未运行 |
| Apple、Paraformer、Qwen | #15–16 | M5 签名窗口与 420 段公开人声。Zipformer 仍仅供研究 |

## 最终体验入口

本次唯一候选为 `1.0.0-rc.2-integrated.1`，Apple Silicon、macOS 26 或更高版本。DMG 为 63,471,583 字节，包含签名 App、三个消费者入口及按需下载机制。产品源码为 `235b29447ed04e0ef8ccf167e1314f756596e747`，DMG 的 SHA-256 为 `7c5dd932b64ef7a4ffde710df75ab41c062fe76845b70cc007dd3a34a31d51b9`。后续提交仅包含验收驱动、证据和交付资料。[安装包与回退说明](../deliverables/v1-integrated/) · [逐项机器记录](../evidence/v1-integrated/acceptance.json)

首次安装默认本机识别。有明确 BYOK 或 Cloud 偏好的旧用户继续使用已选来源。用户开启收音时处理麦克风授权。可选 GPT 文字核对及音频上传分别受已有凭据和授权约束。消费者目录保留 Apple、轻量的 Paraformer 和手动选择的 Qwen。原生窗口以活动 ASR 的实词显示，暂停、待命及音量反馈继续使用底部状态键。独立复核将批准原图与最终窗口逐项比对，查看了浅蓝和暗色两个受控背景的实际 WindowServer 合成、短文、长文、选区与跨日回看。透明度会随背景变化，最终个人审美判断留给集中体验。[批准原图](../design/approved/Saytile-original-visual-reference-20261107.jpeg) · [实拍对照](../evidence/v1-integrated/backdrops/) · [实际讲话窗口录像](../evidence/v1-integrated/apple-window.mp4) · [滚动与留白录像](../evidence/v1-integrated/timeline/idle-transition.mov)

## Qwen 与长期收音

原先停显的公开混说片段中，Qwen 将已显示的中文由繁体改为简体。显示层的逐字前缀检查阻止后续有效内容出现。新版只在比较临时候选前缀时考虑繁简对应，显示内容逐字来自模型。Qwen 临时假设的可外派长度仍为零。摄取层将短 PCM 帧合并到 100 毫秒，600 个缓冲槽可容纳约一分钟单声道 PCM，结束时冲刷短尾。历史取消收据只记录了 CancellationError，无法从它单独区分缓冲溢出和任务超时。

M5 24 GiB、macOS 27.0、同样的 15 个公开真人片段、交替启动两个签名 App，每次独立模型、原速回放。两版最终均错 55/568 字，CER 9.68%。[逐句与窗口数据](../evidence/v1-integrated/qwen-ab.json)

| 原速窗口指标 | PR #16 同机复测 | 整合候选 |
|---|---:|---:|
| 原先问题片段最长有效停显 | 5.33 秒 | 1.60 秒 |
| 15 段最长有效停显 | 5.33 秒 | 3.93 秒 |
| 首字 P50 / P95 | 0.92 / 0.96 秒 | 0.94 / 1.23 秒 |
| 有效更新间隔 P95 | 1.60 秒 | 1.65 秒 |
| 可见尾部回改总数 | 24 | 28 |
| 十秒以上语音在结束前多次有效出字 | 5/5 | 5/5 |

**PASS** · 持续 1,803 秒，以公开语音和停顿形成 102 段。同时运行 Accelerate CPU 矩阵运算和 Metal GPU 运算。102 段均完成，原音逐段可读、时间轴完整、外派为零。App 前后五分钟 RSS 中位数为 71.2 → 58.0 MiB，Qwen 助手为 736.3 → 731.7 MiB。此前 101/102 的共享负载结果保留。此次竞争负载可复现，强度并非此前所有后台任务的精确重建。[半小时核对](../evidence/v1-integrated/qwen-shared.json) · [计算负载](../evidence/v1-integrated/compute.log)

**PASS** · Qwen 损坏时保存原音，恢复权重后在原记录重新识别，WAV 哈希和时间轴 ID 保持一致。两句话之间有 45 秒静音时，助手退出，再于下一段重新启动。独立冷启动时 App 与助手同时采样的物理内存峰值为 Apple 34、Paraformer 506、Qwen 1,352 MiB。Qwen 的整机空闲及活动均值为 11.20 W 和 14.45 W，均在交流电测量。暂停状态另测 300 秒。[原音恢复与助手生命周期](../evidence/v1-integrated/qwen-fault.json) · [四路 CPU、GPU、ANE 及系统内存采样](../evidence/v1-integrated/resource/) · [待机采样](../evidence/v1-integrated/idle.json)

## 输入、资料、下载与权限

- **PASS** · 完整 Xcode 上 413 项 Swift 测试、108 项 AppModel 检查。隔离原生 TextKit 对 12,000 条历史执行翻页、选区保护、编辑与复制。真实 AppKit、WKWebView、TextEdit 及 Chrome 使用生产 AX 范围与所有权检查。另对 headless Chrome 的 textarea 和 contenteditable 运行 20 项 DOM 检查。首次极简 Chrome 测试页缺少编辑框外的语义锚点，未取得所有权。在有独立页面标题和草稿标签的隔离浏览器里，首插、增量派发、去重、外围文本保留及目标变更停投通过。[产品源码原生测试](../evidence/v1-integrated/native-ci.log) · [浏览器和原生记录](../evidence/v1-integrated/input/)
- **PASS** · 实际 RC1 的 v2 资料与冻结 RC2 的 v5 资料均升级至 v6。隔离 Keychain canary、原音、历史、草稿及云授权保留，旧程序拒绝更新版资料库，可恢复匹配的备份。SIGKILL 和事务回滚验证覆盖未确认外派及只删原音。[RC1 升级](../evidence/v1-integrated/upgrade-rc1.json) · [RC2 升级](../evidence/v1-integrated/upgrade-v5.json) · [崩溃恢复](../evidence/v1-integrated/crash.json)
- **PASS** · 独立 macOS 从空目录下载两款消费者权重，通过暂停、续传、完整哈希、重开与删除。受控离线后从已保存的前缀恢复，错误范围被拒绝。容量预检保留录音余量，下载错误在自动和手动设置中均可见。[公开 CDN](../evidence/v1-integrated/download-ci.log) · [网络中断测试](../evidence/v1-integrated/download-interruption.log)
- **FAIL** · 本机现有代理下 Qwen 整包冷下载仍中断。请求与整段资源传输设有时限和有限重试，用户可以继续下载或使用系统识别。已安装模型可离线使用。[本机失败记录](../evidence/v1-integrated/host-cold.log)
- **PASS** · 同源的隔离 macOS HAL 音频设备回放合成语音，暂停状态及恢复后旧 WAV 字节正确。实际断开测试机网络时，新语音仍能入档。设备权限恢复、物理耳机切换及真实睡眠分别保留适用边界。[设备、网络与权限记录](../evidence/v1-integrated/device/)
- **PASS（隔离）** · 正式 AppModel 能在本机、BYOK、Cloud 间切换。真实 Keychain 测试账户及本地协议服务器完成保存、刷新、删除、独立授权、一路 ASR 和可选文字核对。真实付费供应商及商业收费上线为 **NOT_RUN**。[本地服务记录](../evidence/v1-integrated/hosted-loopback.log)

## 分发与后续条件

集成 Sparkle 2.10.1，使用固定哈希引入官方 framework。只有签名构建同时配置 HTTPS feed 和 Ed25519 公钥才启动更新器。测试在临时目录、小范围 loopback feed、独立应用 ID 和一次性密钥上运行官方 sparkle-cli。损坏包签名失败，旧版继续可用；恢复正确签名包后从版本 1 更新至 2，旧库可重新打开，缓存标记的内容与修改时间不变。同版本随后报告没有新版本。候选未配置公共 feed。将来启用通道时，需要打包带正式公钥和 feed 的新签名基础版，保管签名私钥，并为 feed 和更新归档分别签名。[隔离更新收据](../evidence/v1-integrated/update.json) · [Sparkle 官方文档](https://sparkle-project.org/documentation/)

本轮工程验收支持进入集中体验。尚未发现会丢失原音、覆盖编辑或错投文字的已知 P0/P1。公证前的 Gatekeeper 返回 `Unnotarized Developer ID`，面向普通下载用户的公开发行仍为 **BLOCKED**。真实 8 GB 内存压力、离电续航、特定实体耳机热插拔和本次内核级睡眠为 **NOT_RUN**。隔离主机没有可撤销再恢复的原有麦克风授权，该组合为 **BLOCKED**。真实云端接入与付费是后续独立验收。客户无需录音排查或收集日志。[签名](../evidence/v1-integrated/signature.log) · [Gatekeeper](../evidence/v1-integrated/gatekeeper.log)

工程复测可用 `scripts/build-update-test-cli.sh` 构建固定版本的上游 CLI，再运行 `scripts/test-integrated-update.py`。安装包仅内嵌更新框架。故障注入会在临时目录重签两个隔离副本，临时密钥随测试结束删除。真实发布时，使用固定 HTTPS feed，在构建环境设置 `SAYTILE_UPDATE_FEED` 与公开的 `SAYTILE_UPDATE_PUBLIC_KEY`。正式密钥的保管及公开发布通道由发行环节处理。

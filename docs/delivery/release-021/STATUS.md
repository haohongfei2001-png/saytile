# Saytile 0.21（564）Release Closure

2026-11-23（Asia/Shanghai）。唯一发行裁决：**HOLD，不应公开推广**。当前授权下可执行的 A–E 工程与验收已收口；压力响应性仍 FAIL，公证授权 BLOCKED，不能把测试完成或 CI 全绿当作产品放行。

- 产品源码：`06997bd613ac4dede54450702385259f3bc02f2c`；签名包 0.21（564）。后续提交仅测试、证据和文档，运行时树相同。
- 主线候选：[Draft PR #52 → main](https://github.com/haohongfei2001-png/saytile/pull/52)，直接基于 main `4caf73c85e31a5c49de70c3430a84d4504aa701f`。#49/#50/#51 保留历史且标注承接关系。
- DMG SHA-256：`4c86d8cd7a29f7bce4682bf8fd994ab251e1d86f8914c38a470d96426eb13be7`，65,600,572 bytes。
- [完整验收与剩余限制](ACCEPTANCE.md) · [机器总收据](../../../evidence/release-021/machine.json) · [源码及技术边界](ARCHITECTURE.md) · [安装回退](../../INTERNAL-INSTALL.md)。

## A — 基线与隔离

刷新远端 main / PR49–51 / CI，核验 563 包及现用 533。测试使用公开人声和独立合成档案；没有读取生产文字或录音，没有改现用 App、资料、Keychain、模型缓存。完整来源见 `evidence/release-021/baseline.json`。

## B — 连续文字发布

同一批 34 份原始候选离线重放，两轮有明确假设的算法尝试均 FAIL：局部锚点接续未消除原有间隔；禁止旧词回返扩大到 8.948–9.914 秒。拒绝进入产品，保留 563 生产算法与全部失败证据。没有第三轮无收益优化，没有增加生产 ASR。

签名 563 / 564 完成三组有效原速压力配对，旧/新最大有效可见间隔依次 1.987/2.370、3.420/3.368、1.999/2.000 秒。新候选仍 FAIL；CPU 未证明改善。无效负载和计算干扰轮次完整保留并说明排除理由。

## C — 空定稿

五个切片逐帧匹配完整公开语料，位于独立 Apple 正文识别区间外；Qwen 原片及诊断增益均空。最可能是非语音触发，但没有足够证据宣称绝对静音。全部仍失败可重试，原音和已有文字不删。修正空 EOS 被误报为“未收到定稿”的提示与分类，保留健康 worker；有/无预览及用户编辑的回归通过。详细逐项诊断见 `evidence/release-021/empty-final`。

## D — 最终源码验证

- PASS：15 段原速 CER 46/568 = 8.10%，全部讲话中多次出字；首字 P95 1.499 秒、新字间隔 P95 1.020 秒、EOS P95 0.284 秒、局部往返回改 0。
- PASS：固定 420 段 910/10663 = 8.53%，派生 20 段另列 8.51%；440 条最终文字及状态均与基线相同，五个失败子段没有改为成功。
- PASS：905 秒原生连续运行、18 项存储/异常子进程、隔离 533→564→533→564、真实 Sparkle 安装与损坏包拒绝、原生编辑/复制/档案/菜单/品牌往返。
- PASS：完整 Xcode 的 568 Swift Testing + 30 XCTest；测试修复后真实 AppKit / WKWebView / TextEdit / Chrome / Edge / Safari 前台输入均通过。产品所有权约束没有放宽。VirtualMac 系统睡眠实际 BLOCKED，独立披露。
- 保留首次原速进程退出原因 UNKNOWN、批量 CLI 错误工作目录、首次 Safari 测试光标初始化、缺失测试源及旧清单校验失败的原始证据。后续复测不掩盖它们。
- 最终证据提交还会触发完整 CI；以 PR #52 当前 head 的实际 checks 为准，不把上一提交 CI 冒充新提交结果。CI 最终收据在 PR 与交付目录关联该 head，避免为了记录同一次成功不断产生新源码版本。

## E — 发行与边界

Developer ID、安全时间戳及 App/DMG strict 校验 PASS。实际 Gatekeeper App/DMG 均拒绝 `Unnotarized Developer ID`；没有装订票据。普通/同步 Keychain 公证 profile 元数据均 0，Actions secret 名称列表为空。公证 BLOCKED，不清除 quarantine、不绕过安全机制。账户持有人只需在本机交互式运行 `xcrun notarytool store-credentials saytile-release` 配置授权；无需把密钥给聊天。授权仅解决公证，不自动解除压力 HOLD。

正式分支选择性纳入需要的产品、依赖与测试，不合并历史分支链或旧 DMG。修正构建号依赖 Git 提交数导致的倒退风险，固定为 564；官网和公开更新源保留 main。候选仅存于交付目录，没有安装第二份产品，没有合并或公开发布。

iCloud entitlement 缺失、反馈发送关闭，真实云同步/反馈 NOT_RUN；不宣传已同步，不上传私人数据。它们不是首个本地 Beta 的绝对前置条件。合盖麦克风、额外物理设备、真实 8 GB 与整机功耗 NOT_RUN。

后续放行必须先取得可量化的压力响应性收益并回归，再对真正待发行包公证和 Gatekeeper 检查。当前工作不擅自扩大算法尝试次数或公开安装范围。

# Saytile 1.0.1（576）— 签名候选，发行 HOLD

最终产品源码 `2d12129f2031fdf827d51fa1796d155e79243e07`，SourceDirty=false。PR #56 面向 main，当前安装0.20（533）保持原样；没有合并、公开发行、切换官网或生产更新源，也没有访问个人档案、录音或密钥正文。

## 已完成

- 首次使用只展示一次本机模型准备入口；解释模型体积、麦克风和可选辅助功能权限，拒绝麦克风后可以进入恢复入口。
- 修复AX读取错误类型丢失与缺失角色被误判为明确不可编辑。未知状态只能在已发出的一次写入后进入既有有限确认；明确禁用、只读、目标或编辑变化仍立即拒绝。没有增加写入、抢焦点或自动发送。
- 修复Sparkle真正调用的Release Notes delegate；正式版本展示移除遗留“内测”前缀。默认更新窗口的CI宿主补齐真实图标，原IconServices失败保留。
- 完整Xcode CI `27e7586`：583 Swift Testing +30 XCTest、零失败；native、foreground、品牌、设计、模拟云协议全部通过。真实隔离AppKit/WKWebView/TextEdit/Chrome/Edge/Safari通过。默认Sparkle窗口展示、发行说明与稍后关闭通过。
- 原速对照：15段CER 8.10%，420段8.5344%；完整440样本最终文字/状态新旧一致。五个失败子段保留，不改成成功。完整语料实测产品574；到576识别/存储/发布源码逐对象相同，旧证据不改SHA。
- 576签名App：56次AXPress与编辑/复制/星标重启；4场景真实WindowServer截图；38.8s公开音频实时原生出字与档案一致。已有904.83s持续运行及空闲释放证据保留其实际源码。
- 576重新执行18项存储故障/恢复回归；只读DMG隔离安装、离线启动、篡改拒绝、0.18/533程序副本升级回退全部通过。真实572→576 Sparkle安装、坏包拒绝、回退及六个模型文件712,777,119字节SHA/mtime保留通过。
- 官网当前1.0.0下载已核验；1.0.1 FAQ/元数据已准备并通过本地检查，尚未提前部署未公证版本。

## 发布裁决

**HOLD。** Developer ID、安全时间戳和资源签名通过；App与DMG的Gatekeeper实际拒绝 `Unnotarized Developer ID`，未找到现成公证授权。公证前不发布新版本或启用生产更新。

性能能力仍有限：原速15段候选首字P95 2.126s，原长句最大有效可见间隔3.085s；后续三对复测未重现这些离群值，但不构成根治或CPU改善。880840e的Chrome原失效细因仍UNKNOWN；分类缺陷已修、定向故障与新真实前台测试通过，不承诺所有网页AX异常消失。持续不可读时保留文字并安全停派发。

最终DMG：`dist/1.0.1/Saytile-1.0.1-arm64.dmg`，65,617,522字节，SHA-256 `9c3d18e26b2d9085fc0e71c3bc4da5183c028432cbc95efc55d5eda0e7290d1f`。

[完整验收](docs/delivery/release-101/ACCEPTANCE.md) · [机器交付收据](evidence/release-101/DELIVERY.json) · [性能及原始失败](docs/delivery/release-101/PERFORMANCE.md)。

## 最小外部依赖

账户持有人在本机为Team ZB9D4T66QB配置一次notarytool profile，密码只交给Apple本机工具，不发送到聊天。之后还必须真实公证、装订、重签更新文件、Gatekeeper及下载验收；这些没有执行，不算PASS。合盖内置麦克风、8GB实体Mac、物理断电NOT_RUN。iCloud和私有反馈服务未启用，不宣传未验证能力。

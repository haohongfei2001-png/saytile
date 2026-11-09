# 单 ASR 封版验收进行中

d71912a 已在独占前台通过原生输入、重复、后缀、无法确认后不重放及换窗拒投。WKWebView 的 DOM 已出现正确文字，但协调器返回 unverified，计 FAIL。真实设备、12 项存储恢复和 8 项安装回退已通过。

本机已通过 399 项 Swift Testing、104 项 AppModel 和 52 个环回协议用例。第一次托管 Xcode 完成 Swift 全量测试，随后发现旧诊断参数会走普通启动路径；现已在创建资料库前明确拒绝该参数，并保留旧入口防回归检查。独立前台夹具与设计 CI 环境正在同批复测。

原始分支本机 Swift Testing 全量运行发现 399 项测试、47 个问题。隔离 WKWebView 中，AXSelectedText 成功返回却没有写入；同一系统公开的 AXReplaceRangeWithText 真实写入预期中文与 emoji。变更保留写后读回、目标身份和不重放检查，完整 Xcode 与前台场景等待最终源码复测。

# V1 测试结果 · no-api.9.1

当前设备修补候选来自[运行源码 `0a0cdeca`](https://github.com/haohongfei2001-png/saytile/commit/0a0cdecab8eb099e1dc3bb21b4c15ba5c30c93f0)。[固定安装包](https://raw.githubusercontent.com/haohongfei2001-png/saytile/5ff88cb3ccf7c6ff4afb2f95360f5798d0be3632/deliverables/no-api.9.1/Saytile-1.0.0-rc.2-no-api.9.1-arm64.dmg) · [完整实机报告](../evidence/no-api9.1/README.md) · [逐项机器验收](../evidence/no-api9.1/snapshots/public/machine.json)。

基线 no-api.9 的显式设备装配路径在同款计数探针中触发 AVFAudio 格式异常，直接中止进程。修补版明确选麦时按 UID 打开系统输入队列，继续使用原有音频日志和识别工作线程。设备移除会中断采集，必须明确选择可用设备才会恢复。

本阶段 11 项 PASS，3 项 FAIL，7 项 BLOCKED。正常 TextEdit 前台投递已实测；WKWebView 投递未确认，目标改变后没有重试或发送。受控睡眠后暂停标签仍旧是 P2。普通 Gatekeeper 执行拒绝；本包仅为 ad-hoc 工程候选。

三家真实云服务、真人准确率、相比最强单模型的收益与确认延迟均待凭据与授权。实际系统睡眠与第二支独立物理麦克风保留各自状态。标准公开分发需要发行方 Developer ID 签名和公证。

72 小时实时时钟的计划终点为北京时间 2026-11-10 19:54；终态以实际收据为准。

[原冻结版记录](https://github.com/haohongfei2001-png/saytile/blob/45256e38fb2d52d1c583965bb259d3c27edafc79/docs/V1-NO-API-DELIVERY.md) · [安装与数据回退](V1-INSTALL.md)。
